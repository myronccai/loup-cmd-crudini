# Design: crudini

## Overview

`bin/crudini.lpscr` is a `host.scripted` script and the only code that
reads files, prints and exits. Its top-level statements parse `args()`
into a `Request`, handle `--help` and `--version`, read the config file
into an `IniDocument`, run every operation through one `Editor`, and then
either print what `--get` produced or write the changed document the way
the options ask. Everything else lives in `lib/`, as `host.scripted`
modules (sets, unions matched by type and `Any` make them scripts) plus two
`host.dual` modules of constants and text.

```text
args() ─ parse_command_line ─► Request (operations + Settings namespace)
FILE ─ readLines ─► IniDocument.read ─ scan_line ─► Section blocks of Entry | string
stdin (--merge) ─ data.ini.parse ─► dict[string, dict[string, string]]
Editor.apply(op) ─► output lines (--get) │ changed document
render ─ encode ─► writeLines (temp + rename) │ writeLines / appendText (--inplace) │ stdout
```

## Modules

| Module | Mode | Contents |
|---|---|---|
| `bin/crudini.lpscr` | scripted | top level: command line, reading, operations, writing, `--verbose` |
| `lib/appinfo.loup` | dual | name, version, exit statuses |
| `lib/usage.loup` | dual | `usage()`, `version_line()` |
| `lib/options.lpscr` | scripted | `Mode`, `Operation`, the option table, `dynamic class Settings`, the `setting_flag!`/`setting_text!` macros, `parse_command_line`, `existing_mode`, `list_separator`, `ini_options` |
| `lib/lexer.lpscr` | scripted | `LineKind`, `LineToken[~src]`, `scan_line` |
| `lib/entry.lpscr` | scripted | `Entry` (a parameter), `entry_from_token` |
| `lib/section.lpscr` | scripted | `Section implements Dynamic` |
| `lib/document.lpscr` | scripted | `IniDocument`: reading, queries, structural edits, `render`, `encode` |
| `lib/editor.lpscr` | scripted | `Editor`: `--get`, `--set`, `--del`, `--merge`, `--existing`, lists |
| `lib/listval.lpscr` | scripted | `ListSep`, `update_list` |
| `lib/printers.lpscr` | scripted | `Printer`, `IniPrinter`, `IniNoSpacePrinter`, `LinesPrinter`, `ShPrinter` |
| `lib/storage.lpscr` | scripted | `read_config`, `read_problem`, `write_problem`, `replace_file`, `rewrite_in_place` |
| `lib/errors.lpscr` | scripted | `CrudiniError` and its subclasses |

### Command line

crudini's grammar has verbs that may repeat, so the parser follows
crudini's own: a first pass groups words (`--get`, `--set`, `--del` and
`--merge` start an operation, plain words are its operands, `--name` words
are options and take the next word when the table says so), a second pass
stores the options in order, a third checks the operations.

The options live in a `dynamic class Settings`, like an argparse namespace:
the parser stores each option under its name from the option table
(`setField("list_sep", ...)`), so adding an option means adding a table
row. A table row's initial value and every parsed value are `bool | string`
(true for a flag or a bare `--existing`, text otherwise; `false` marks
`--list-sep` as not given, so an empty separator stays distinguishable).
Validation matches these unions by type. Readers use the typed getter
macros `setting_flag!(settings, "inplace")` and `setting_text!(...)`, which
expand to `settings.getField(name) as bool` / `as string`, or a dynamic
view (`dynamic settings as s { s.format }`, in `Editor`'s constructor).
Long options may be abbreviated to a unique prefix, as with Python's
getopt.

### Reading

`scan_line` returns a `LineToken[lifetime ~src]`, a struct whose `text`
field borrows the line (`borrow[~src] text: string`) and holds offsets of
the name, separator, value and inline comment. `IniDocument.read` copies out
only what an `Entry` keeps. Its rules are iniparse's: the first `=` or `:`
separates name and value, a line without either is a flag (a bare name), a
`;` after whitespace starts an inline comment, an indented line continues
the value above it (blank and comment lines between continuation lines
join the value), and an indented line that continues nothing is an error
unless `--ini-options=ignoreindent`. Comment and blank lines wait in a
pending list until the next line shows where they belong.

The document is a list of `Section` blocks: the first holds what comes
before any header (the implicit part of `DEFAULT`); every header starts
another block, and blocks with the same name act as one section. A block's
body is a `list[Entry | string]`: parameters and verbatim lines, rendered
by matching each item's type. An `Entry` renders the line it was read from
until it is edited; then it rebuilds `indent + name + separator + value`
and puts an inline comment back in its column. `Entry.section` is a `weak`
back-pointer to its block, so an entry can name its section and remove
itself (`detach`) without keeping the block alive. `entry.lpscr` and
`section.lpscr` import each other; the entry side uses
`from .section defer import (Section)`.

`Section implements Dynamic`: its fields are its parameters (`getField`
gives the value, `setField(name, "text")` sets or inserts one,
`setField(name, true)` inserts a bare name, `deleteField` removes every
occurrence, `fieldNames` lists them once), so `sec!{port}` reads a
parameter.

### Operations

`Editor` ports crudini's methods:

- `get` (command_get): plain, ini, lines and sh output through the printer
  for `--format`; whole-file listings show `DEFAULT` first when it has
  parameters. Values are looked up with inheritance from `DEFAULT`.
- `set_value` (set_name_value): `--existing=param`/`section` checks, a
  missing section added at the end after a blank line, a value-less
  parameter written as a bare name when the file has bare names, `--list`
  updates through `update_list` (starting from the inherited value), then
  the section's own last occurrence is assigned or a new entry inserted
  after the section's last parameter.
- `delete` (command_del): a parameter (every occurrence, through
  `Entry.detach`), a section (all its blocks; blank lines tidied as
  iniparse's `tidy()` does), `DEFAULT` (its fields and any header).
- `merge` (command_merge): over the `data.ini` document of standard input
  (`sections`, `getSection`, `getValue`), skipping a section's parameter
  equal to the input's own `DEFAULT` value and adding empty sections.

Missing items throw `NoSectionError(section)` / `NoOptionError(param)`.

### Output

- `--format=ini` uses `data.ini.stringify` for `[section]` and
  `name = value`; `IniNoSpacePrinter` writes `name=value` itself.
- `--format=sh` quotes values with `core.shlex.quote` and refuses names
  that are not shell identifiers (a `set[string]` of allowed characters).
- `IniDocument.render` gives logical lines (optionally tidied, or spaced by
  `sectionspace`), `encode` puts a byte order mark and CRs back.
- The file is written only when its text changed (or to another
  `--output`): by default to `FILE.crudini-N.tmp` (a copy of the old file,
  so it keeps the permission bits), then renamed over it, inside
  `try`/`finally` that removes the temporary file; with `--inplace` by
  `writeLines` on the file itself, or `appendText` of the new lines when
  the change only appends and the file still holds exactly what was read.
- `--verbose` quotes the last operation's words with `core.shlex.quote`.

## Differences from the original

- Messages start with `crudini: `, and usage errors print a one-line hint
  instead of the whole usage. File errors read
  `crudini: FILE: No such file or directory` rather than Python's
  `[Errno 2] ...`; parse errors name the file and line.
- Extra operands are an error (crudini ignores them).
- There is no file locking (Loup has none). `--inplace` re-reads the file
  before appending instead.
- The default replacement keeps permission bits but not ownership, and
  replaces a symbolic link with a regular file (crudini follows the link);
  use `--inplace` to write through a link.
- `--get SECTION` lists the section's own parameters; crudini hides those
  whose value equals the `DEFAULT` one.
- `--merge` reads its input with `data.ini`, which knows `name = value` and
  `name: value` lines only: continuation lines and bare names in the input
  are skipped. `--merge -` (config file from standard input) is refused.
- `--output=FILE` naming another file always writes it; crudini skips the
  write when nothing changed.
- A file without a final newline counts as unchanged when no operation
  changes it (crudini adds the newline and rewrites).
- `sectionspace` only adjusts blank lines before section headers (crudini's
  pattern also matches `[...]` inside values).

## Error handling

- Command-line errors: `crudini: MESSAGE` (plus the `Try` hint for usage
  errors) on standard error, status 1, nothing read or written.
- The file is checked with `exists`/`isDir` before reading, because the
  self-hosted `loup run` cannot catch `IoError`. A missing file is an error
  for `--get` and with `--existing`; otherwise it reads as empty.
- Parse errors and operation errors (`CrudiniError`) print their message
  and exit 1; `--get` prints what it found before the failing item first.
  Nothing is written when any operation fails.
- An unwritable target ends the run with the runtime's `IoError` (status
  1); a missing target directory is reported first.

## Testing

- `tests/lexer_test.lpscr`: line kinds, offsets, inline comments, headers,
  continuation and `ignoreindent`.
- `tests/document_test.lpscr`: unchanged round trip, BOM and CRLF, lookups
  and inheritance, dynamic access, the weak back-pointer, comment columns,
  section edits and tidying, `sectionspace`, styles, parse errors, and
  rendered output read back with `data.ini`.
- `tests/editor_test.lpscr`: every operation and format, lists, merge,
  `--existing`.
- `tests/options_test.lpscr`, `tests/listval_test.lpscr`,
  `tests/printers_test.lpscr`, `tests/storage_test.lpscr` (files under
  `build/tmp/`).
- `tests/e2e.sh`: the script under `loup run` against
  `tests/fixtures/app.ini`; edits are checked as `diff FIXTURE RESULT`,
  plus permissions, links, `--output`, standard input, BOM and CRLF,
  `--verbose` and usage errors.
