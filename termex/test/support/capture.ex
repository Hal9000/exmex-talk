defmodule Termex.Capture do
  @moduledoc false

  alias Termex.Device

  @spec open(String.t()) :: {Device.t(), pid()}
  def open(input \\ "") do
    {:ok, input_dev} = StringIO.open(input)
    {:ok, output_dev} = StringIO.open("")
    {Device.pair(input_dev, output_dev), output_dev}
  end

  @spec text(pid()) :: String.t()
  def text(output_dev) do
    {_input, output} = StringIO.contents(output_dev)
    output
  end
end
