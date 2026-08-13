defmodule Tidex.OpenTest do
  use ExUnit.Case, async: true

  test "editor command true returns after the process exits" do
    assert :ok = Tidex.Open.editor("true")
  end
end
