defmodule Tidex.FailuresTest do
  use ExUnit.Case, async: true

  alias Tidex.Failures

  @exunit """
  Finished in 0.3 seconds
    1) test Foo.bar/1 (FooTest)
       test/foo_test.exs:12
       Assertion with == failed
       code:  assert Foo.bar() == :ok
       left:  :error
       right: :ok
       stacktrace:
         test/foo_test.exs:12: (test)

    2) test boom (FooTest)
       test/foo_test.exs:20
       ** (RuntimeError) timed out
       stacktrace:
         test/foo_test.exs:20: (test)
  """

  @minitest """
  Run options: --seed 1234

  # Running:

  FE

    1) Failure:
  CalculatorTest#test_add [test/calculator_test.rb:8]:
  Expected: 5
    Actual: 4

    2) Error:
  CalculatorTest#test_divide:
  ZeroDivisionError: divided by 0
      test/calculator_test.rb:13:in `/'

  2 runs, 1 assertions, 1 failures, 1 errors, 0 skips
  """

  test "parses ExUnit failure blocks into name, file, line, and snippet" do
    [one, two] = Failures.parse(@exunit)

    assert one.name == "test Foo.bar/1 (FooTest)"
    assert one.file == "test/foo_test.exs"
    assert one.line == 12
    assert one.snippet =~ "Assertion with == failed"

    assert two.name == "test boom (FooTest)"
    assert two.file == "test/foo_test.exs"
    assert two.line == 20
    assert two.snippet =~ "RuntimeError"
  end

  test "unknown output yields no failures" do
    assert Failures.parse(["ok", "everything passed"]) == []
  end

  test "parses non-test ExUnit headings such as properties and setup callbacks" do
    output = """
      1) property addition is commutative (MathPropertyTest)
         test/math_property_test.exs:14
         Failed with generated values

      2) MathTest: failure on setup_all callback, all tests have been invalidated
         test/math_test.exs:5
         ** (RuntimeError) setup failed
    """

    [property, setup] = Failures.parse(output, :exunit)
    assert property.name =~ "property addition"
    assert property.file == "test/math_property_test.exs"
    assert setup.name =~ "setup_all callback"
    assert setup.file == "test/math_test.exs"
  end

  test "parses Minitest failures and errors when configured" do
    [failure, error] = Failures.parse(@minitest, :minitest)

    assert failure.name == "CalculatorTest#test_add"
    assert failure.file == "test/calculator_test.rb"
    assert failure.line == 8
    assert failure.snippet == "Expected: 5 · Actual: 4"

    assert error.name == "CalculatorTest#test_divide"
    assert error.file == "test/calculator_test.rb"
    assert error.line == 13
    assert error.snippet =~ "ZeroDivisionError"
  end

  test "none format deliberately disables failure parsing" do
    assert Failures.parse(@exunit, :none) == []
  end

  test "cycle wraps left and right" do
    state = %{failures: [%{name: "a"}, %{name: "b"}, %{name: "c"}], failure_index: 0}
    assert Failures.cycle(state, 1).failure_index == 1
    assert Failures.cycle(state, -1).failure_index == 2
    assert Failures.current(Failures.cycle(state, 1)).name == "b"
  end

  test "modal is a 60x8 fail box from the current failure" do
    state = %{
      failures: [
        %{
          name: "test Foo.bar/1 (FooTest)",
          file: "test/foo_test.exs",
          line: 12,
          snippet: "Assertion with == failed · code:  assert 1"
        },
        %{
          name: "test boom (FooTest)",
          file: "test/foo_test.exs",
          line: 20,
          snippet: "** (RuntimeError) timed out"
        }
      ],
      failure_index: 1,
      width: 80,
      height: 24
    }

    refute Failures.modal(%{failures: []})

    modal = Failures.modal(state)
    assert modal.kind == :fail
    assert modal.title == "fail 2/2"
    assert modal.min_width == 60
    assert modal.max_width == 60
    assert modal.min_height == 8
    assert modal.max_height == 8
    assert hd(modal.lines) == "test boom (FooTest)"
    assert Enum.at(modal.lines, 1) == "test/foo_test.exs:20"
    assert Enum.at(modal.lines, 2) =~ "RuntimeError"
    pane = Tidex.Modal.pane(state, modal)
    assert pane.width == 60
    assert pane.height == 8
  end

  test "showing? is true only on a failed run with parsed failures" do
    refute Failures.showing?(%{test_state: :fail, failures: []})
    refute Failures.showing?(%{test_state: :pass, failures: [%{name: "a"}]})
    assert Failures.showing?(%{test_state: :fail, failures: [%{name: "a"}]})
  end
end
