require "date"
require "set"

module Drivy
  class PricingViewer
    attr_reader :cars, :rentals, :pricing, :rental_changes

    def initialize(data = {})
      @cars = Car.load(data["cars"])
      @rentals = Rental.load(data["rentals"], cars)
      @rental_changes = RentalChange.load(data["rental_modifications"], rentals)
    end

    # View of modifications
    def modifications
      {
        "rental_modifications" => rental_changes.map do |(id, rental_change)|
          with_type, pricing = Pricing.delta_by_actor(rental_change)
          {
            "id" => id,
            "rental_id" => rental_change.rental_id,
            "actions" => [
              {
                "who" => "driver",
                "type" => with_type[Pricing::DEBIT],
                "amount" => pricing.driver
              },
              {
                "who" => "owner",
                "type" => with_type[Pricing::CREDIT],
                "amount" => pricing.owner
              },
              {
                "who" => "insurance",
                "type" => with_type[Pricing::CREDIT],
                "amount" => pricing.insurance
              },
              {
                "who" => "assistance",
                "type" => with_type[Pricing::CREDIT],
                "amount" => pricing.assitance
              },
              {
                "who" => "drivy",
                "type" => with_type[Pricing::CREDIT],
                "amount" => pricing.drivy
              }
            ]
          }
        end
      }
    end
  end

  class Pricing
    attr_reader :rental

    # Discount
    PER_DAY_DISCOUT = [
      {over: 10, percent: 50},
      {over: 4, percent: 30},
      {over: 1, percent: 10},
      {over: 0, percent: 0}
    ]

    # Fees share
    COMMISSION = 0.3
    ASSURANCE_SHARE = 0.5
    ASSISTANCE_COST = 100 # € By Day (be aware: README give a bad value)
    DEDUCTIBLE_COST = 400 # € By Day (be aware: README give a bad value)

    # Bank operation
    DEBIT = "debit"
    CREDIT = "credit"
    BANK_OP_INVERSE = {DEBIT => CREDIT, CREDIT => DEBIT}

    def initialize(rental)
      @rental = rental
    end

    # Total of price by day with degressive rule
    def self.degressive_price(price_per_day, duration)
      prev_over = nil
      PER_DAY_DISCOUT.inject(0) do |acc, discount|
        next acc unless duration > discount[:over]
        days = (prev_over ? prev_over : duration) - discount[:over]
        prev_over = discount[:over]
        acc += (price_per_day - price_per_day * (discount[:percent] / 100.0)) * days
      end.round(0)
    end

    # Get price by actor based on delta from a rental change (#by_actor) and an
    # helper to get the correct bank operation (fn[CREDIT | DEBIT]).
    def self.delta_by_actor(rental_change)
      original = Pricing.new(rental_change.rental).by_actor
      pricing = Pricing.new(rental_change.generate_rental).by_actor
      add_charges = original.driver < pricing.driver
      pricing.members.each do |k|
        pricing[k] = add_charges ? pricing[k] - original[k] : original[k] - pricing[k]
      end
      return fn_operation_type(add_charges), pricing
    end

    def self.fn_operation_type(add_charges)
      -> (operation) { add_charges ? operation : BANK_OP_INVERSE[operation] }
    end

    def commission
      @commission ||= (price * COMMISSION).round(0)
    end

    # Rental's price
    def price
      @price ||= (
        Pricing.degressive_price(rental.car.price_per_day, rental.duration) +
        rental.car.price_per_km * rental.distance
      )
    rescue Drivy::NotFound => e
      raise "Can't compute the price. #{e.message}"
    end

    # Sharing fees between actors (insurance, assistance, drivy)
    def fees
      @fees ||= {
        "insurance_fee" => (commission * ASSURANCE_SHARE).round(0),
        "assistance_fee" => (ASSISTANCE_COST * rental.duration).round(0)
      }.tap { |fees| fees["drivy_fee"] = commission - fees.values.inject(:+) }
    end

    def deductible_reduction
      @deductible_reduction ||= (
        rental.deductible_reduction ? rental.duration * DEDUCTIBLE_COST : 0
      )
    end

    def by_actor
      Struct.new(:driver, :owner, :insurance, :assitance, :drivy).new(
        price + deductible_reduction,             # driver
        price - commission,                       # owner
        fees["insurance_fee"],                    # insurance
        fees["assistance_fee"],                   # assitance
        fees["drivy_fee"] + deductible_reduction  # drivy
      )
    end
  end

  class Car < Struct.new(:id, :price_per_day, :price_per_km)
    def self.load(hsh)
      (hsh || {}).each_with_object({}) { |h, memo| memo[h["id"]] = new(h) }
    end

    def initialize(hsh = {}, cars = nil)
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
    end
  end

  module DateCompute
    # Days beetween start_date & end_date
    def duration
      return 0 if end_date == nil || start_date == nil
      (end_date - start_date).to_i + 1
    end

    private

    # Convert fields content from string to date
    def set_date(*fields)
      fields.each do |field|
        next unless self.respond_to?(field) && self[field].is_a?(String)
        self[field] = Date.strptime(self[field], "%Y-%m-%d")
      end
    end
  end

  module LinkedModel
    def get_linked_model(klass, hsh, obj_id)
      return if obj_id == nil
      unless hsh && hsh.key?(obj_id)
        name = klass.name.split('::').last
        raise NotFound.new(
          self.class.const_get("#{name.upcase}_NOT_FOUND") % [id, obj_id]
        )
      end
      hsh[obj_id]
    end
  end

  class Rental < Struct.new(:id, :car_id, :start_date, :end_date, :distance, :deductible_reduction)
    attr_reader :cars

    include DateCompute
    include LinkedModel

    CAR_NOT_FOUND = "Rental %d link car_id to an unknow Car (id %d)"

    def self.load(hsh, cars = nil)
      (hsh || {}).each_with_object({}) { |h, memo| memo[h["id"]] = new(h, cars) }
    end

    def initialize(hsh = {}, cars = nil)
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
      set_date(:start_date, :end_date)
      @cars = cars if cars.is_a?(Hash)
    end

    def car
      get_linked_model(Car, @cars, car_id)
    end
  end

  class RentalChange < Struct.new(:id, :rental_id, :start_date, :end_date, :distance)
    include DateCompute
    include LinkedModel

    RENTAL_NOT_FOUND = "RentalChange %d link rental_id to an unknow Rental (id %d)"
    RENTAL_UPD_KEYS = (Set.new(Rental.members) & Set.new(members)).delete(:id)

    def self.load(hsh, rentals = nil)
      (hsh || {}).each_with_object({}) { |h, memo| memo[h["id"]] = new(h, rentals) }
    end

    def initialize(hsh = {}, rentals = nil)
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
      set_date(:start_date, :end_date)
      @rentals = rentals if rentals.is_a?(Hash)
    end

    def rental
      get_linked_model(Rental, @rentals, rental_id)
    end

    def generate_rental
      rental.dup.tap do |updated|
        RENTAL_UPD_KEYS.each { |k| updated[k] = self[k] if self[k] }
      end
    end
  end

  class NotFound < StandardError; end
end
