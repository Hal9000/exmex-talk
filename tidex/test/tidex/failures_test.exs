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

  test "cycle wraps left and right" do
    state = %{failures: [%{name: "a"}, %{name: "b"}, %{name: "c"}], failure_index: 0}
    assert Failures.cycle(state, 1).failure_index == 1
    assert Failures.cycle(state, -1).failure_index == 2
    assert Failures.current(Failures.cycle(state, 1)).name == "b"
  end

  test "showing? is true only on a failed run with parsed failures" do
    refute Failures.showing?(%{test_state: :fail, failures: []})
    refute Failures.showing?(%{test_state: :pass, failures: [%{name: "a"}]})
    assert Failures.showing?(%{test_state: :fail, failures: [%{name: "a"}]})
  end
end
