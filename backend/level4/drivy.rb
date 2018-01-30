require "date"

module Drivy
  class PricingViewer
    attr_reader :cars, :rentals, :pricing

    def initialize(data = {})
      @cars = Car.load(data["cars"] || {})
      @rentals = Rental.load((data["rentals"] || {}), cars)
      @pricing = Pricing.new
    end

    # View of gains
    def gains()
      { "rentals" => rentals.map do |(id, rental)|
          price = pricing.get_price(rental)
          fees = pricing.get_fees(price, rental)
          {
            "id" => id,
            "price" => price,
            "options" => {
              "deductible_reduction" => pricing.get_deductible_reduction(rental)
            },
            "commission" => fees
          }
        end
      }
    end
  end

  class Pricing
    PER_DAY_DISCOUT = [
      {over: 10, percent: 50},
      {over: 4, percent: 30},
      {over: 1, percent: 10}
    ]

    COMMISSION = 0.3
    ASSURANCE_SHARE = 0.5
    ASSISTANCE_COST = 100 # € By Day (be aware: challenge give a bad value)
    DEDUCTIBLE_COST = 400 # € By Day (be aware: challenge give a bad value)

    def initialize
      per_day_discount
    end

    # Rental's price
    def get_price(rental)
      degressive_price(rental.car.price_per_day, rental.duration) +
      rental.car.price_per_km * rental.distance
    rescue Drivy::Rental::NotFound => e
      raise "Please, check your source : #{e.message}"
    end

    # Sharing fees between actors (insurance, assistance, drivy)
    def get_fees(price, rental)
      commission = (price * COMMISSION).round(0)
      {
        "insurance_fee" => (commission * ASSURANCE_SHARE).round(0),
        "assistance_fee" => (ASSISTANCE_COST * rental.duration).round(0)
      }.tap do |fees|
        fees["drivy_fee"] = commission - (fees["insurance_fee"] + fees["assistance_fee"])
      end
    end

    def get_deductible_reduction(rental)
      return 0 unless rental.deductible_reduction
      rental.duration * DEDUCTIBLE_COST
    end

    # Total of price by day with degressive rule
    def degressive_price(price_per_day, duration)
      per_day_discount.inject(0) do |acc, discount|
        next acc unless duration > discount[:over]
        days = duration - discount[:over]
        days = discount[:duration] if discount[:duration] && days > discount[:duration]
        acc += (price_per_day - price_per_day * (discount[:percent] / 100.0)) * days
      end.round(0)
    end

    # Generate an internal hash to help to compute degressive price
    def per_day_discount
      @per_day_discount ||= begin
        (PER_DAY_DISCOUT + [{over: 0, percent: 0}]).each_with_index.map do |slice, idx|
          {
            over: slice[:over],
            duration: (idx > 0) ? PER_DAY_DISCOUT[idx - 1][:over] - slice[:over] : nil,
            percent: slice[:percent]
          }.freeze
        end
      end
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
      return unless cars
      @cars = cars if cars.is_a?(Hash)
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
