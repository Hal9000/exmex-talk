defmodule Tidex.ServerProbe do
  @moduledoc false

  @type status :: :listening | :closed | :unsupported

  @spec status(String.t() | nil, timeout()) :: status()
  def status(url, timeout \\ 100)

  def status(url, timeout) when is_binary(url) do
    case local_target(url) do
      {:ok, targets, port} ->
        if Enum.any?(targets, &connectable?(&1, port, timeout)),
          do: :listening,
          else: :closed

      :unsupported ->
        :unsupported
    end
  end

  def status(_url, _timeout), do: :unsupported

  @spec wait_closed(String.t() | nil, non_neg_integer()) :: :closed | :listening | :unsupported
  def wait_closed(url, timeout \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_closed_until(url, deadline)
  end

  @spec local_port(String.t()) :: {:ok, :inet.port_number()} | :unsupported
  def local_port(url) when is_binary(url) do
    case local_target(url) do
      {:ok, _targets, port} -> {:ok, port}
      :unsupported -> :unsupported
    end
  end

  defp local_target(url) do
    uri = URI.parse(url)
    host = if is_binary(uri.host), do: String.downcase(uri.host)

    with {:ok, targets} <- local_addresses(host),
         port when is_integer(port) <- uri.port || default_port(uri.scheme),
         true <- port > 0 and port <= 65_535 do
      {:ok, targets, port}
    else
      _ -> :unsupported
    end
  rescue
    _ -> :unsupported
  end

  defp local_addresses("localhost") do
    {:ok, [{{127, 0, 0, 1}, []}, {{0, 0, 0, 0, 0, 0, 0, 1}, [:inet6]}]}
  end

  defp local_addresses("127.0.0.1"), do: {:ok, [{{127, 0, 0, 1}, []}]}
  defp local_addresses("::1"), do: {:ok, [{{0, 0, 0, 0, 0, 0, 0, 1}, [:inet6]}]}
  defp local_addresses(_host), do: :unsupported

  defp connectable?({address, options}, port, timeout) do
    case :gen_tcp.connect(address, port, [:binary, active: false] ++ options, timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp wait_closed_until(url, deadline) do
    case status(url) do
      :listening ->
        if System.monotonic_time(:millisecond) >= deadline do
          :listening
        else
          Process.sleep(25)
          wait_closed_until(url, deadline)
        end

      status ->
        status
    end
  end

  defp default_port("http"), do: 80
  defp default_port("https"), do: 443
  defp default_port(_scheme), do: nil
end
