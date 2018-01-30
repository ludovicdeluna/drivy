require 'minitest/autorun'
require 'json'
require_relative "./drivy"

class TestDrivy < Minitest::Test
  def test_pricing_per_day_discount
    expected = [
      {over: 10, duration: nil, percent: 50},
      {over: 4,  duration: 6,   percent: 30},
      {over: 1,  duration: 3,   percent: 10},
      {over: 0,  duration: 1,   percent:  0}
    ]
    assert_equal Drivy::Pricing.new.per_day_discount, expected
  end

  def test_pricingviewer_gains
    expected = JSON.parse(File.read("output.json"))
    data = JSON.parse(File.read("data.json"))
    assert_equal Drivy::PricingViewer.new(data).gains, expected
  end
end
