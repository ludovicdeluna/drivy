require "date"

module Drivy
  class Pricing
    PER_DAY_DISCOUT = [
      {over: 10, percent: 50},
      {over: 4, percent: 30},
      {over: 1, percent: 10}
    ]

    # View of gains
    def gains(data = {})
      cars = Car.load(data["cars"] || {})
      rentals = Rental.load(data["rentals"] || {})
      {
        "rentals" => rentals.map do |(_, rental)|
          {
            "id" => rental.id,
            "price" => pricing(cars[rental.car_id], rental)
          }
        end
      }
    end

    # Price Calculation of a rental
    def pricing(car, rental)
      degressive_price(car.price_per_day, rental.duration) +
      car.price_per_km * rental.distance
    end

    # Compute total price on degressive basis of per day price
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

    def initialize(hsh = {})
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
    end
  end


  class Rental < Struct.new(:id, :car_id, :start_date, :end_date, :distance)
    def self.load(hsh)
      hsh.each_with_object({}) { |h, memo| memo[h["id"]] = new(h) }
    end

    def initialize(hsh = {})
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      super(*hsh.values_at(*members.map(&:to_s)))
      set_date(:start_date)
      set_date(:end_date)
    end

    # Days beetween start_date & end_date
    def duration
      return 0 if end_date == nil || start_date == nil
      (end_date - start_date).to_i + 1
    end

    private

    def set_date(field)
      return unless self.respond_to?(field) && self[field].is_a?(String)
      self[field] = Date.strptime(self[field], "%Y-%m-%d")
    end
  end
end
