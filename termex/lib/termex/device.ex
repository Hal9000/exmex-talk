defmodule Termex.Device do
  @moduledoc """
  An injectable input/output pair.

  The live app uses `:stdio`. Tests pass `StringIO` pids so drawing and
  keypresses can be asserted without a real TTY.
  """

  defstruct input: :stdio, output: :stdio

  @type t :: %__MODULE__{input: IO.device(), output: IO.device()}

  @spec stdio() :: t()
  def stdio, do: %__MODULE__{}

  @spec pair(IO.device(), IO.device()) :: t()
  def pair(input, output), do: %__MODULE__{input: input, output: output}
end
