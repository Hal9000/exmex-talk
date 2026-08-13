defmodule Tidex.FakeTerminal do
  @moduledoc false

  @spec open(String.t()) :: {Termex.Device.t(), pid()}
  def open(input \\ "") do
    {:ok, input_dev} = StringIO.open(input)
    {:ok, output_dev} = StringIO.open("")
    {Termex.Device.pair(input_dev, output_dev), output_dev}
  end

  @spec text(pid()) :: String.t()
  def text(output_dev) do
    {_input, output} = StringIO.contents(output_dev)
    output
  end
end
