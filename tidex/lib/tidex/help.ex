defmodule Tidex.Help do
  @moduledoc false

  alias Tidex.{Modal, Scroll}

  @menu_width 46
  @text_width 46

  @topics [
    %{
      id: :tests,
      title: "Tests",
      summary: "run and read status",
      paragraphs: [
        "Press t from the lobby to run the project's configured test command. Tidex stays on the lobby while output is collected in the background.",
        "The Test status moves through idle, running, pass, and fail. While tests run, parsed ExUnit failure headers update the fail count.",
        "A successful run clears earlier failures. A nonzero exit with no recognizable failure block still reports fail."
      ]
    },
    %{
      id: :failures,
      title: "Failures",
      summary: "inspect and edit",
      paragraphs: [
        "After a failed test run, press f to open the failure box. If Tidex parsed no failures, f does nothing.",
        "Use left and right to move between failures. Press e to yield the terminal to your configured editor at the current file and line.",
        "Esc or f closes the failure box. The complete test log is retained but is not dumped onto the lobby."
      ]
    },
    %{
      id: :server,
      title: "Server",
      summary: "start, stop, browse",
      paragraphs: [
        "The Server group reports the project server managed by Tidex. Its command and browser URL come from tidex.conf.",
        "If server is omitted, the unchanged Server box says [No server configured] and shows no controls. Tidex does not assume that Python or another language runtime is installed.",
        "Press s on the lobby to start the server. Pressing s again stops the tracked job and starts a new one. Press x to stop and b to open the configured URL.",
        "For a local browser URL, starting means the owned job is alive but the port is closed; up means it is listening. A pre-existing listener is reported as port busy and is never killed."
      ]
    },
    %{
      id: :git,
      title: "Git",
      summary: "status and commands",
      paragraphs: [
        "The lobby marks Git as dirty without showing branch details. Press i for a compact branch and change-count summary, or g for the full Git status box.",
        "Inside Git, a stages tracked changes with git add -u, l pulls only a fast-forward, c prompts for a one-line commit message, and p pushes.",
        "Arrows and Page Up or Page Down scroll long status and command output. Esc returns to the lobby."
      ]
    },
    %{
      id: :files,
      title: "Files & config",
      summary: "project shortcuts",
      paragraphs: [
        "Press 0 to edit the project's tidex.conf. Keys 1 through 4 open the corresponding file1 through file4 entries.",
        "Project configuration supplies the label, test command, ExUnit or Minitest failure format, server command, browser URL, editor, and optional file shortcuts.",
        "The editor falls back through the user Tidex config, VISUAL, EDITOR, and finally vi."
      ]
    },
    %{
      id: :navigation,
      title: "Navigation",
      summary: "keys and modal rules",
      paragraphs: [
        "Tidex uses single-key commands; Enter is not required. Bold letters in the lobby are available commands.",
        "At most one modal box sits over the lobby. A modal seals unrelated keys, Esc backs out, and q always quits Tidex.",
        "In this Help menu, Tab or the arrow keys select a topic and Enter opens it. Topic text scrolls with arrows or Page Up and Page Down."
      ]
    }
  ]

  @spec modal() :: Modal.t()
  def modal do
    menu(0)
  end

  @spec move(Modal.t(), integer()) :: Modal.t()
  def move(%Modal{kind: :help, page: :menu} = modal, delta) do
    selection = Integer.mod(modal.selection + delta, length(@topics))
    menu(selection)
  end

  @spec open(Modal.t()) :: Modal.t()
  def open(%Modal{kind: :help, page: :menu} = modal) do
    topic = Enum.at(@topics, modal.selection)

    %{
      modal
      | page: {:topic, topic.id},
        title: "help · #{topic.title}",
        lines: topic_lines(topic),
        commands: "↑/↓ pgup/pgdn scroll   esc topics   ? close",
        scroll: 0
    }
  end

  @spec back(Modal.t()) :: Modal.t()
  def back(%Modal{kind: :help} = modal), do: menu(modal.selection)

  @spec scroll(Modal.t(), term(), %{width: pos_integer(), height: pos_integer()}) :: Modal.t()
  def scroll(%Modal{kind: :help, page: {:topic, _}} = modal, key, screen) do
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

  defp menu(selection) do
    %Modal{
      kind: :help,
      title: "help",
      page: :menu,
      selection: selection,
      lines: menu_lines(selection),
      commands: "tab/↑↓ select   enter open   esc close",
      min_width: 50,
      max_width: 50,
      min_height: 10,
      max_height: 10
    }
  end

  defp menu_lines(selection) do
    @topics
    |> Enum.with_index()
    |> Enum.map(fn {topic, index} ->
      text = "#{topic.title} — #{topic.summary}" |> String.pad_trailing(@menu_width)

      if index == selection do
        "> " <> Termex.reverse(text)
      else
        "  " <> text
      end
    end)
  end

  defp topic_lines(topic) do
    topic.paragraphs
    |> Enum.map(&wrap(&1, @text_width))
    |> Enum.intersperse([""])
    |> List.flatten()
  end

  defp wrap(text, width) do
    text
    |> String.split()
    |> Enum.reduce([], fn word, lines ->
      case lines do
        [line | rest] when byte_size(line) + byte_size(word) + 1 <= width ->
          [line <> " " <> word | rest]

        _ ->
          [word | lines]
      end
    end)
    |> Enum.reverse()
  end
end
