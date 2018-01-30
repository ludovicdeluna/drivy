require "date"

module Drivy
  # Calculate gains for each rental
  def self.gains(data = {})
    cars = Car.load(data["cars"] || {})
    rentals = Rental.load(data["rentals"] || {})
    {
      "rentals" => rentals.map do |(_, rental)|
        {
          "id" => rental.id,
          "price" => price(cars[rental.car_id], rental)
        }
      end
    }
  end

  # level1 rule for pricing calculation
  def self.price(car, rental)
    car.price_per_day * rental.duration + car.price_per_km * rental.distance
  end
end

module Drivy
  class Car < Struct.new(:id, :price_per_day, :price_per_km)
    def self.load(hsh)
      hsh.each_with_object({}) { |h, memo| memo[h["id"]] = new(h) }
    end

    def initialize(hsh = {})
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      self.members.map(&:to_s).each { |k, _| self[k] = hsh[k] if hsh.key?(k) }
    end
  end


  class Rental < Struct.new(:id, :car_id, :start_date, :end_date, :distance)
    def self.load(hsh)
      hsh.each_with_object({}) { |h, memo| memo[h["id"]] = new(h) }
    end

    def initialize(hsh = {})
      raise "Need a hash for initialize" unless hsh.is_a?(Hash)
      self.members.map(&:to_s).each { |k, _| self[k] = hsh[k] if hsh.key?(k) }
      self.start_date = Date.strptime(start_date, "%Y-%m-%d") if start_date
      self.end_date = Date.strptime(end_date, "%Y-%m-%d") if end_date
    end

    # Days beetween start_date & end_date
    def duration
      return 0 if end_date == nil || start_date == nil
      (end_date - start_date).to_i + 1
    end
  end
end
