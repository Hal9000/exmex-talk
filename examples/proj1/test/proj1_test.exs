defmodule Proj1Test do
  use ExUnit.Case, async: true

  test "hello returns :world" do
    assert Proj1.hello() == :world
  end

  test "add/2" do
    assert Proj1.add(1, 2) == 3
  end

  test "this fails on purpose (for the Tidex failure box)" do
    assert Proj1.add(2, 2) == 5
  end
end
