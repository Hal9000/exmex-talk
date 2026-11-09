defmodule Tidex.Help do
  @moduledoc false

  alias Tidex.{Modal, Scroll}

  @outer_width 64
  @outer_height 18

  @sections [
    %{
      title: "Tests",
      paragraphs: [
        "Press t from the lobby to run the project's configured test command. Tidex stays on the lobby while output is collected in the background.",
        "The Test status moves through idle, running, pass, and fail. While tests run, recognized failure headers update the fail count.",
        "A successful run clears earlier failures. A nonzero exit with no recognizable failure block still reports fail."
      ]
    },
    %{
      title: "Failures",
      paragraphs: [
        "After a failed test run, press f to open parsed test failures or recognized compiler diagnostics. If Tidex recognized neither, the same key opens the raw command output instead.",
        "Use left and right to move between failures. Press e to open the reported location. If the failure can be traced to a specific project source location, the s command is shown for that secondary candidate.",
        "Compiler diagnostics use the same left, right, and e controls. Press o to inspect their complete command output.",
        "An assertion often identifies only its test line; Tidex cannot reliably infer where the underlying defect lives.",
        "Press o for the complete test output; Esc returns to the failure. Esc closes the failure box. Output scrolls with arrows or Page Up and Page Down."
      ]
    },
    %{
      title: "Server",
      paragraphs: [
        "The Server group reports the project server managed by Tidex. Its command and browser URL come from tidex.conf.",
        "If server is omitted, the unchanged Server box says [No server configured] and shows no controls. Tidex does not infer a runtime or default server command.",
        "Press s on the lobby to start the server. Pressing s again stops the tracked job and starts a new one. Press x to stop, b to open the configured URL, and v to inspect server output.",
        "If server startup fails with recognized compiler diagnostics, their modal opens automatically. Press o there for complete server output; v always means view output from the lobby.",
        "For a local browser URL, starting means the owned job is alive but the port is closed; up means it is listening. A pre-existing listener is reported as port busy and is never killed."
      ]
    },
    %{
      title: "Git",
      paragraphs: [
        "The lobby marks Git as dirty without showing branch details. Press i for a compact branch and change-count summary, or g for the full Git status box.",
        "Inside Git, a stages tracked changes with git add -u, l pulls only a fast-forward, c prompts for a one-line commit message, and p pushes. The u ship command stages tracked changes, commits, rebases on the remote, then pushes; it stops at the first failure.",
        "Arrows and Page Up or Page Down scroll long status and command output. Esc returns to the lobby."
      ]
    },
    %{
      title: "Files & config",
      paragraphs: [
        "Press 0 to edit the project's tidex.conf. Tidex reloads it when the editor returns. Keys 1 through 4 open the corresponding file1 through file4 entries.",
        "Project configuration supplies the label, test command, failure format (ExUnit, Minitest, or none), server command, browser URL, editor, and optional file shortcuts.",
        "The editor falls back through the user Tidex config, VISUAL, EDITOR, and finally vi."
      ]
    },
    %{
      title: "Navigation",
      paragraphs: [
        "Tidex uses single-key commands; Enter is not required. Bold letters in the lobby are available commands.",
        "At most one modal box sits over the lobby. A modal seals unrelated keys, Esc backs out, and q always quits Tidex.",
        "Help is one document. Scroll it with arrows or Page Up and Page Down; Esc closes it."
      ]
    }
  ]

  @spec modal(%{width: pos_integer(), height: pos_integer()}, Scroll.t()) :: Modal.t()
  def modal(screen \\ %{width: 80, height: 24}, scroll \\ 0) do
    width = min(@outer_width, max(screen.width - 2, 2))
    height = min(@outer_height, max(screen.height - 2, 2))

    %Modal{
      kind: :help,
      title: "help",
      page: :document,
      lines: document_lines(max(width - 2, 1)),
      commands: "↑/↓ pgup/pgdn scroll   esc close",
      scroll: scroll,
      min_width: width,
      max_width: width,
      min_height: height,
      max_height: height
    }
  end

  @spec scroll(Modal.t(), term(), %{width: pos_integer(), height: pos_integer()}) :: Modal.t()
  def scroll(%Modal{kind: :help, page: :document} = modal, key, screen) do
    body_height = Modal.body_height(screen, modal)

    delta =
      case key do
        :up -> -1
        :down -> 1
        :page_up -> -max(body_height, 1)
        :page_down -> max(body_height, 1)
      end

    %{modal | scroll: Scroll.step(modal.lines, body_height, modal.scroll, delta)}
  end

  defp document_lines(width) do
    @sections
    |> Enum.flat_map(fn section ->
      [Termex.bold(String.upcase(section.title))] ++
        Enum.flat_map(section.paragraphs, fn paragraph -> [""] ++ wrap(paragraph, width) end) ++
        [""]
    end)
    |> Enum.drop(-1)
  end

  defp wrap(text, width) do
    text
    |> String.split()
    |> Enum.reduce([], fn word, lines ->
      case lines do
        [line | rest] ->
          if String.length(line) + String.length(word) + 1 <= width do
            [line <> " " <> word | rest]
          else
            [word | lines]
          end

        _ ->
          [word | lines]
      end
    end)
    |> Enum.reverse()
  end
end
