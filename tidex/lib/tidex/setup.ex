defmodule Tidex.Setup do
  @moduledoc false

  alias Tidex.Config

  defstruct cwd: ".",
            git_root: nil,
            blocked: false,
            offer_cwd: false,
            offer_git: false

  @type t :: %__MODULE__{
          cwd: String.t(),
          git_root: String.t() | nil,
          blocked: boolean(),
          offer_cwd: boolean(),
          offer_git: boolean()
        }

  @spec needed?(String.t()) :: boolean()
  def needed?(cwd), do: Config.find_file(cwd) == nil

  @spec probe(String.t()) :: t()
  def probe(cwd) do
    cwd = Path.expand(cwd)
    git_root = Config.git_root(cwd)
    blocked = Config.blocked?(cwd)

    offer_git =
      is_binary(git_root) and git_root != cwd and not Config.blocked?(git_root)

    %__MODULE__{
      cwd: cwd,
      git_root: git_root,
      blocked: blocked,
      offer_cwd: not blocked,
      offer_git: offer_git
    }
  end

  @spec lines(t() | nil) :: [String.t()]
  def lines(nil), do: ["no tidex.conf"]

  def lines(%__MODULE__{offer_cwd: false} = setup) do
    [
      "no tidex.conf",
      "",
      "cwd is not permitted",
      blocked_label(setup.cwd)
    ] ++ git_option(setup) ++ ["", "n or esc  skip"]
  end

  def lines(%__MODULE__{offer_git: true} = setup) do
    if Config.project_markers?(setup.cwd) do
      cwd_first(setup)
    else
      git_first(setup)
    end
  end

  def lines(%__MODULE__{} = setup), do: cwd_only(setup)

  defp cwd_only(setup) do
    [
      "no tidex.conf",
      "",
      "write in cwd?",
      setup.cwd,
      "",
      "y  write here",
      "n or esc  skip"
    ]
  end

  defp cwd_first(setup) do
    [
      "no tidex.conf",
      "",
      "write in cwd?",
      setup.cwd,
      "",
      "y  write here",
      "g  git root  #{setup.git_root}",
      "n or esc  skip"
    ]
  end

  defp git_first(setup) do
    [
      "no tidex.conf",
      "",
      "cwd doesn't look like a project",
      "git root:",
      setup.git_root,
      "",
      "g  write at git root",
      "y  write in cwd anyway",
      "n or esc  skip"
    ]
  end

  defp git_option(%{offer_git: true, git_root: root}) when is_binary(root) do
    ["", "g  write at git root", root]
  end

  defp git_option(_), do: []

  defp blocked_label(cwd) do
    home = System.user_home()

    cond do
      is_binary(home) and Path.expand(cwd) == Path.expand(home) -> "$HOME"
      cwd in ["/", "/tmp", "/var", "/private/tmp", "/private/var"] -> cwd
      true -> cwd
    end
  end
end
