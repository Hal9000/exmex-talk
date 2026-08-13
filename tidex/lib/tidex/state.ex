defmodule Tidex.State do
  @moduledoc false

  defstruct title: "Tidex",
            project_name: "exmex-talk",
            test_state: :idle,
            server_state: :idle,
            test_command: "mix test",
            server_command: "python3 -m http.server 4000",
            output_lines: [],
            output_source: nil,
            test_ref: nil,
            test_pid: nil,
            server_ref: nil,
            server_pid: nil,
            width: 80,
            height: 24

  @type status :: :idle | :running | :pass | :fail | :stopped

  @type t :: %__MODULE__{
          title: String.t(),
          project_name: String.t(),
          test_state: status(),
          server_state: status(),
          test_command: String.t(),
          server_command: String.t(),
          output_lines: [String.t()],
          output_source: :test | :server | nil,
          test_ref: reference() | nil,
          test_pid: pid() | nil,
          server_ref: reference() | nil,
          server_pid: pid() | nil,
          width: pos_integer(),
          height: pos_integer()
        }
end
