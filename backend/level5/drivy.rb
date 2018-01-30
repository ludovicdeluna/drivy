require "date"

module Drivy
  class PricingViewer
    attr_reader :cars, :rentals, :pricing

    def initialize(data = {})
      @cars = Car.load(data["cars"] || {})
      @rentals = Rental.load((data["rentals"] || {}), cars)
    end

    # View of operations
    def operations
      { "rentals" => rentals.map do |(id, rental)|
          pricing = Pricing.new(rental).by_actor
          {
            "id" => id,
            "actions" => [
              {
                "who" => "driver",
                "type" => "debit",
                "amount" => pricing.driver
              },
              {
                "who" => "owner",
                "type" => "credit",
                "amount" => pricing.owner
              },
              {
                "who" => "insurance",
                "type" => "credit",
                "amount" => pricing.insurance
              },
              {
                "who" => "assistance",
                "type" => "credit",
                "amount" => pricing.assitance
              },
              {
                "who" => "drivy",
                "type" => "credit",
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

    PER_DAY_DISCOUT = [
      {over: 10, percent: 50},
      {over: 4, percent: 30},
      {over: 1, percent: 10},
      {over: 0, percent: 0}
    ]

    COMMISSION = 0.3
    ASSURANCE_SHARE = 0.5
    ASSISTANCE_COST = 100 # € By Day (be aware: README give a bad value)
    DEDUCTIBLE_COST = 400 # € By Day (be aware: README give a bad value)

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

    def commission
      @commission ||= (price * COMMISSION).round(0)
    end

    # Rental's price
    def price
      @price ||= (
        Pricing.degressive_price(rental.car.price_per_day, rental.duration) +
        rental.car.price_per_km * rental.distance
      )
    rescue Drivy::Rental::NotFound => e
      raise "Please, check your source : #{e.message}"
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
      hsh.each_with_object({}) { |h, memo| memo[h["id"]] = new(h) }
    end

    def initialize(hsh = {}, cars = nil)
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
    end
  end

  class Rental < Struct.new(:id, :car_id, :start_date, :end_date, :distance, :deductible_reduction)
    CAR_NOT_FOUND = "Rental %d has no car for car_id %d"

    def self.load(hsh, cars = nil)
      hsh.each_with_object({}) { |h, memo| memo[h["id"]] = new(h, cars) }
    end

    def initialize(hsh = {}, cars = nil)
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
      set_date(:start_date)
      set_date(:end_date)
      return unless cars.is_a?(Hash)
      @cars = cars
    end

    # Days beetween start_date & end_date
    def duration
      return 0 if end_date == nil || start_date == nil
      (end_date - start_date).to_i + 1
    end

    # Get car details for this rental
    def car
      return if car_id == nil
      raise NotFound.new(CAR_NOT_FOUND % [id, car_id]) unless @cars && @cars.key?(car_id)
      @cars[car_id]
    end

    private

    def set_date(field)
      return unless self.respond_to?(field) && self[field].is_a?(String)
      self[field] = Date.strptime(self[field], "%Y-%m-%d")
    end
  end
  class Rental::NotFound < StandardError; end
end
