defmodule Proj1.Server do
  @response "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: 12\r\n\r\nproj1 alive\n"

  def run(port \\ 4000) do
    {:ok, listener} =
      :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])

    IO.puts("proj1 listening on http://localhost:#{port}")
    accept(listener)
  end

  defp accept(listener) do
    {:ok, socket} = :gen_tcp.accept(listener)

    spawn(fn ->
      _ = :gen_tcp.recv(socket, 0, 1_000)
      :ok = :gen_tcp.send(socket, @response)
      :gen_tcp.close(socket)
    end)

    accept(listener)
  end
end

Proj1.Server.run()
