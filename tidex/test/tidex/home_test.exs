defmodule Tidex.HomeTest do
  use ExUnit.Case, async: true

  alias Tidex.Home

  setup do
    dir = Path.join(System.tmp_dir!(), "tidex-home-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{home: dir}
  end

  test "load is empty when the user file is missing", %{home: home} do
    assert Home.load(home: home) == %Home{}
  end

  test "parses editor and dir: name catalog entries", %{home: home} do
    File.write!(Path.join(home, "tidex.conf"), """
    # user
    editor: nvim
    /tmp/demo-project: demo
    ~/other: other
    project: ignored
    """)

    user = Home.load(home: home)
    assert user.editor == "nvim"
    assert user.catalog[Path.expand("/tmp/demo-project")] == "demo"
    assert user.catalog[Path.expand("~/other")] == "other"
    refute Map.has_key?(user.catalog, "project")
  end

  test "remember writes dir: name and keeps editor", %{home: home} do
    assert :ok = Home.write!(%Home{editor: "hx"}, home: home)
    assert :ok = Home.remember("/tmp/alpha", "alpha", home: home)

    body = File.read!(Path.join(home, "tidex.conf"))
    assert body =~ ~r/^editor: hx$/m
    assert body =~ ~r|^/tmp/alpha: alpha$|m

    user = Home.load(home: home)
    assert user.editor == "hx"
    assert Home.lookup(user, "/tmp/alpha") == "alpha"
  end
end
