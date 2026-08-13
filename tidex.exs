%{
  test: "mix test",
  server: "python3 -m http.server 4000",
  browser: "http://localhost:4000",
  editor: System.get_env("VISUAL") || System.get_env("EDITOR") || "vi"
}
