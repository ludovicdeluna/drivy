require 'minitest/autorun'
require 'json'
require_relative "./drivy"

class TestDrivy < Minitest::Test
  def test_gains
    expected = JSON.parse(File.read("output.json"))
    data = JSON.parse(File.read("data.json"))
    assert_equal Drivy.gains(data), expected
  end
end
