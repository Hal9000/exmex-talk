defmodule Tidex.State do
  @moduledoc false

  defstruct title: "Tidex",
            project_name: "exmex-talk",
            statuses: [{"tests", "idle"}, {"git", "idle"}],
            command: "echo hello from tidex",
            command_output: "",
            last_status: nil

  @type t :: %__MODULE__{
          title: String.t(),
          project_name: String.t(),
          statuses: [{String.t(), String.t()}],
          command: String.t(),
          command_output: String.t(),
          last_status: nil | non_neg_integer()
        }
end
