defmodule Tidex.ServerProbeTest do
  use ExUnit.Case, async: true

  alias Tidex.ServerProbe

  test "extracts local HTTP and HTTPS ports" do
    assert ServerProbe.local_port("http://localhost:4000/path") == {:ok, 4000}
    assert ServerProbe.local_port("http://LOCALHOST:4567") == {:ok, 4567}
    assert ServerProbe.local_port("http://127.0.0.1") == {:ok, 80}
    assert ServerProbe.local_port("https://[::1]/health") == {:ok, 443}
  end

  test "rejects remote, malformed, and unsupported browser targets" do
    assert ServerProbe.local_port("https://example.com:443") == :unsupported
    assert ServerProbe.local_port("file:///tmp/index.html") == :unsupported
    assert ServerProbe.local_port("not a url") == :unsupported
    assert ServerProbe.status(nil) == :unsupported
  end

  test "reports whether a local port is listening" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    url = "http://localhost:#{port}"

    assert ServerProbe.status(url) == :listening
    :gen_tcp.close(listener)
    assert ServerProbe.status(url) == :closed
  end

  test "wait_closed tolerates a listener that releases shortly after stop" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    url = "http://localhost:#{port}"

    spawn(fn ->
      Process.sleep(50)
      :gen_tcp.close(listener)
    end)

    assert ServerProbe.wait_closed(url, 500) == :closed
  end

  test "localhost detects an IPv6-only loopback listener when available" do
    options = [:binary, :inet6, active: false, ip: {0, 0, 0, 0, 0, 0, 0, 1}]

    case :gen_tcp.listen(0, options) do
      {:ok, listener} ->
        {:ok, port} = :inet.port(listener)
        assert ServerProbe.status("http://localhost:#{port}") == :listening
        :gen_tcp.close(listener)

      {:error, _unsupported} ->
        :ok
    end
  end
end
