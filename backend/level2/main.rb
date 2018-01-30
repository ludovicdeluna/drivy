#!/usr/bin/env ruby
require "json"
require_relative "drivy"

data = JSON.parse(File.read("data.json"))
puts JSON.pretty_generate(Drivy::Pricing.new.gains(data))
