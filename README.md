# loup-cmd-crudini

[crudini](https://github.com/pixelb/crudini) written as a
[Loup](https://code-craft.ai/references/loup) script: it reads and edits INI
files from the command line (`--get`, `--set`, `--del`, `--merge`) and
leaves everything it does not touch exactly as it was, comments, spacing,
line endings and all.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` command: an `.lpscr` entry script in `bin/`
over `.lpscr` modules in `lib/`, run with `loup run`.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later (`loup` and `loup-bootstrap` on `PATH`); see [Installing Loup Lite](#installing-loup-lite).
- `make` and `bash` for the checks and tests. No C compiler: nothing is built.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make run ARGS="--get tests/fixtures/app.ini database"   # loup run bin/crudini.lpscr -- ARGS
make ci                                                 # check, unit tests, end-to-end tests
```

The script is executable (`#!/usr/bin/env -S loup run`). Every crudini
option is a long option, and `loup run` keeps words starting with `--`
before a first `--` for itself, so the arguments go after `--`. With a copy
of [`tests/fixtures/app.ini`](tests/fixtures/app.ini):

```text
$ ./bin/crudini.lpscr -- --get app.ini
DEFAULT
database
server
mysqld
motd
$ ./bin/crudini.lpscr -- --get app.ini database
host
port
user
options
$ ./bin/crudini.lpscr -- --get app.ini server log_level
info
$ ./bin/crudini.lpscr -- --get --format=sh app.ini database
host=db.internal
port=5432
user=app
options=sslmode=require,connect_timeout=10
$ ./bin/crudini.lpscr -- --get --format=lines app.ini motd
[ motd ] text = Welcome to the system.\nMaintenance window: Sunday 02:00.
$ ./bin/crudini.lpscr -- --set app.ini database host db.example.com --set app.ini cache size 64 --verbose
changed: --set app.ini cache size 64
$ ./bin/crudini.lpscr -- --set --list app.ini server plugins cache
$ ./bin/crudini.lpscr -- --del app.ini mysqld
$ cat app.ini
# Example application settings
log_level = info
data_dir = /var/lib/app

[database]
host = db.example.com ; primary server
port = 5432
user = app
options = sslmode=require,connect_timeout=10

[server]
listen: 0.0.0.0:8080
workers = 4
plugins = auth, metrics, cache

[motd]
text = Welcome to the system.
    Maintenance window: Sunday 02:00.

[cache]
size = 64
$ ./bin/crudini.lpscr -- --get app.ini database password
crudini: Parameter not found: password
$ printf '[server]\nworkers = 8\n' | ./bin/crudini.lpscr -- --merge app.ini --output=- | sed -n 10,15p

[server]
listen: 0.0.0.0:8080
workers = 8
plugins = auth, metrics, cache

$ eval "$(./bin/crudini.lpscr -- --get --format=sh app.ini server)"; echo "$workers $plugins"
4 auth, metrics, cache
```

`server log_level` comes from the global section, which every section
inherits from. The comment on `host` stayed where it was, and so did every
line nobody asked to change.

### Operations

| Operation | Meaning |
|---|---|
| `--get FILE [SECTION [PARAM]]` | list the sections, list a section's parameters, or print a value (`-` reads standard input) |
| `--set FILE SECTION [PARAM [VALUE]]` | add or change a parameter (or only make sure the section exists); a missing file is created |
| `--del FILE SECTION [PARAM [VALUE]]` | remove a parameter or a whole section (or, with `--list`, one item of a list) |
| `--merge FILE [SECTION]` | set every parameter of the INI document on standard input, section by section or all into SECTION |

SECTION `""` means the global parameters (those before any header);
`DEFAULT` means the same, but `--set` then gives them a `[DEFAULT]` header.
Several `--set`/`--del` operations, or several `--get` operations, may work
on one file in one command.

### Options

| Option | Meaning |
|---|---|
| `--existing[=WHAT]` | fail when an item is missing: `file`, `section`, or `param` (the default: everything named) |
| `--format=FMT` | `--get` output: `sh` (`name=value` lines to `eval`), `ini`, or `lines` (`[ section ] name = value`) |
| `--ini-options=OPT,...` | `nospace` (`name=value`), `space` (`name = value` everywhere), `sectionspace` (one blank line before each section), `ignoreindent` (indented lines are not continuations) |
| `--inplace` | write the file itself (appending when the change only adds lines) instead of replacing it |
| `--list`, `--list-sep=STR` | treat the value as a list (comma separated, or STR; empty STR: whitespace) and add or remove one item |
| `--output=FILE` | write the result to FILE; `-` is standard output |
| `--verbose` | say `changed: ...` or `unchanged: ...` on standard error |
| `--help` / `--version` | help text / `crudini (loup-cmd-crudini) 0.1.0` |

Options may come anywhere, take their value attached (`--format=sh`) or as
the next word, and may be shortened to a unique prefix (`--form=sh`).

By default a changed file is written to a temporary file next to it (a copy
of the old one, so the permission bits stay) and renamed over it, so a
reader sees the old file or the new one, never half of it. `--inplace`
writes into the file itself, which keeps links, owner and permissions.
Nothing is written when nothing changed.

Exit status: `0` success, `1` any error (a missing section or parameter, an
unreadable or unparsable file, a usage error).

## Differences from the original

- Messages start with `crudini: `; a usage error prints a one-line hint
  instead of the whole usage. File errors read `crudini: FILE: No such file
  or directory` (not Python's `[Errno 2] ...`), and parse errors name the
  file, line and text.
- Extra operands are an error; crudini ignores them silently.
- No file locking (Loup has none). Before appending in place, crudini checks
  that the file still holds exactly what it read.
- The default replacement keeps the permission bits but not the owner, and
  replaces a symbolic link with a regular file (crudini writes through it).
  Use `--inplace` for links.
- `--get SECTION` lists all of the section's own parameters; crudini leaves
  out those whose value equals the `DEFAULT` one.
- `--merge` reads its input with the standard library's `data.ini`, which
  knows `name = value` and `name: value` lines: continuation lines and bare
  names in the merged input are skipped. `--merge -` is refused, since the
  input already comes from standard input.
- `--output=FILE` naming another file always writes it (crudini skips the
  write when nothing changed).
- A file without a final newline that no operation changes is left as it is
  (crudini adds the newline).
- `sectionspace` only changes the blank lines before section headers
  (crudini's pattern also matches `[...]` inside values).

## What this example shows

- **A dynamic class as an argparse namespace.** `lib/options.lpscr` stores
  every option in a `dynamic class Settings` by name from an option table;
  `pub macro setting_flag(...)` / `setting_text(...)` are typed getters
  (`settings.getField(name) as bool`), imported where they are used, and the
  `Editor` reads its settings through a dynamic view
  (`dynamic settings as s { s.format }`).
- **Union types matched by type.** Option values are `bool | string` (a flag,
  or text; `false` marks an option not given), checked with
  `match v { bool(on) => ..., string(text) => ... }`, and a section's body is
  a `list[Entry | string]`: parameters and verbatim lines.
- **`implements Dynamic`.** A `Section`'s fields are its parameters:
  `sec!{port}`, `setField`, `deleteField`, `fieldNames`.
- **`weak` back-pointers and deferred imports.** An `Entry` points back to
  its section with `pub weak var section: Section?` and can remove itself;
  `lib/entry.lpscr` and `lib/section.lpscr` import each other through
  `from .section defer import (Section)`.
- **Lifetimes and borrowed fields.** The scanner's `LineToken[lifetime ~src]`
  borrows the line it describes (`borrow[~src] text: string`) and records
  offsets, so scanning copies nothing.
- **Sets** for comment characters, shell-name characters, the known
  `--ini-options` and section names seen.
- **`data.ini`** (all seven functions: `parse` for `--merge`, `sections`,
  `getSection`, `getValue` while merging, `stringify` for `--format=ini`,
  `hasSection` and `getValueOrDefault` in the tests that read crudini's
  output back), **`io.fs` line APIs** (`readLines`, `writeLines`,
  `appendText`) and **`core.shlex.quote`** for `--format=sh` and
  `--verbose`.
- Also: an exception hierarchy with fields (`NoSectionError(section)`), a
  class hierarchy with `override` and `final` for the output formats,
  `static func` factories, a property getter (`entry.key`), `try`/`finally`
  around the temporary file, a `noreturn` error exit, `box`, `x!`, and a
  `for (var line in lines)` loop.

## Layout

```text
bin/crudini.lpscr           # the command (host.scripted entry script)
lib/appinfo.loup            # name, version, exit statuses
lib/usage.loup              # --help and --version text
lib/options.lpscr           # command line: option table, Settings, getter macros
lib/lexer.lpscr             # line scanner (tokens borrow their line)
lib/entry.lpscr             # a parameter line and its continuation lines
lib/section.lpscr           # a section: Entry | string body, Dynamic
lib/document.lpscr          # the whole file: read, query, edit, render
lib/editor.lpscr            # --get, --set, --del, --merge, --existing, lists
lib/listval.lpscr           # list values (--list, --list-sep)
lib/printers.lpscr          # --format: plain, ini, lines, sh
lib/storage.lpscr           # reading, replacing, writing in place
lib/errors.lpscr            # CrudiniError and its subclasses
tests/*_test.lpscr          # unit tests (make test)
tests/e2e.sh                # end-to-end tests with loup run (make e2e)
tests/fixtures/app.ini      # sample configuration
specs/crudini/              # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
