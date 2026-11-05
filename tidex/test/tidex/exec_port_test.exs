defmodule Tidex.ExecPortTest do
  use ExUnit.Case, async: false

  alias Tidex.ExecPort

  test "concurrent materialization produces one executable helper" do
    cache = Path.join(System.tmp_dir!(), "tidex-exec-port-#{System.unique_integer([:positive])}")
    original = System.get_env("XDG_CACHE_HOME")
    System.put_env("XDG_CACHE_HOME", cache)

    on_exit(fn ->
      if original,
        do: System.put_env("XDG_CACHE_HOME", original),
        else: System.delete_env("XDG_CACHE_HOME")

      File.rm_rf!(cache)
    end)

    paths =
      1..20
      |> Task.async_stream(fn _ -> ExecPort.executable_path() end,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, path} -> path end)

    assert [path] = Enum.uniq(paths)
    assert File.exists?(path)
    assert File.stat!(path).mode |> Bitwise.band(0o100) == 0o100
  end
end
