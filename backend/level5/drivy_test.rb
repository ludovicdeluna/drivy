require 'minitest/autorun'
require 'json'
require_relative "./drivy"

class TestDrivy < Minitest::Test

  def test_pricing_degressive_price
    assert_equal 2000, Drivy::Pricing.degressive_price(2000, 1)
    assert_equal 5600, Drivy::Pricing.degressive_price(2000, 3)
  end

  def test_pricingviewer_get_operations
    expected = JSON.parse(File.read("output.json"))
    data = JSON.parse(File.read("data.json"))
    assert_equal expected, Drivy::PricingViewer.new(data).operations
  end
end
