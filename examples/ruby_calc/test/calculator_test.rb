require "minitest/autorun"
require_relative "../lib/calculator"

class CalculatorTest < Minitest::Test
  def test_add
    assert_equal 5, Calculator.add(2, 2)
  end
end
