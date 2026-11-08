# ruby_calc

A tiny Ruby/Minitest fixture for Tidex. One assertion fails on purpose,
so `t` reports a parsed failure and `f` opens it at the Ruby file and
line.

Build Tidex, then run it here on a real TTY:

```bash
cd ../../tidex
mix escript.build
cd ../examples/ruby_calc
../../tidex/tidex
```

The fixture uses Minitest's standard output format. Its `tidex.conf`
selects that parser explicitly with `test_format: minitest`. Git controls
are disabled because this fixture is only a subdirectory of the enclosing
demo repository.
