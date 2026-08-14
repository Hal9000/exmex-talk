defmodule Tidex.State do
  @moduledoc false

  defstruct title: "Tidex",
            project_name: "exmex-talk",
            test_state: :idle,
            server_state: :down,
            test_command: "mix test",
            server_command: "python3 -m http.server 4000",
            browser_url: "http://localhost:4000",
            editor_command: "vi",
            output_lines: [],
            output_scroll: :follow,
            output_source: nil,
            test_ref: nil,
            test_pid: nil,
            server_ref: nil,
            server_pid: nil,
            git: %{branch: nil, dirty: 0},
            layout: :dashboard,
            width: 80,
            height: 24

  @type test_status :: :idle | :running | :pass | :fail
  @type server_status :: :up | :down
  @type layout :: :dashboard | :output

  @type t :: %__MODULE__{
          title: String.t(),
          project_name: String.t(),
          test_state: test_status(),
          server_state: server_status(),
          test_command: String.t(),
          server_command: String.t(),
          browser_url: String.t(),
          editor_command: String.t(),
          output_lines: [String.t()],
          output_scroll: Tidex.Scroll.t(),
          output_source: :test | :server | nil,
          test_ref: reference() | nil,
          test_pid: pid() | nil,
          server_ref: reference() | nil,
          server_pid: pid() | nil,
          git: Tidex.Git.snapshot(),
          layout: layout(),
          width: pos_integer(),
          height: pos_integer()
        }
end
