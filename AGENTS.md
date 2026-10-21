# AGENTS.md

This repository is `crudini`, a recreation of Pádraig Brady's crudini (query
and edit INI files from the command line) written in the Loup programming
language, part of the loup-cmd series of example applications. It is a
`host.scripted` project: the program is the `.lpscr` script
`bin/crudini.lpscr`, which `loup run` executes from source, over modules in
`lib/`. Nothing is compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/crudini.lpscr), [test] pattern
├── Makefile                     # run, check, test, e2e, ci, clean
├── bin/
│   └── crudini.lpscr            # the command: arguments, reading, operations, writing, exit status
├── lib/                         # modules; host.scripted unless noted
│   ├── appinfo.loup             # host.dual: APP_NAME, APP_VERSION, APP_SUMMARY, exit statuses
│   ├── usage.loup               # host.dual: usage(), version_line()
│   ├── options.lpscr            # Mode, Operation, option table, dynamic class Settings, setting_flag!/setting_text!, parse_command_line()
│   ├── lexer.lpscr              # LineKind, LineToken[~src] (borrows its line), scan_line()
│   ├── entry.lpscr              # class Entry (a parameter; weak back-pointer to its section)
│   ├── section.lpscr            # class Section implements Dynamic (body: list[Entry | string])
│   ├── document.lpscr           # class IniDocument: read, queries, add/remove sections, render, encode
│   ├── editor.lpscr             # class Editor: --get, --set, --del, --merge, --existing, lists
│   ├── listval.lpscr            # enum ListSep, update_list()
│   ├── printers.lpscr           # Printer and its subclasses, one per --format
│   ├── storage.lpscr            # read_config(), replace_file(), rewrite_in_place()
│   └── errors.lpscr             # CrudiniError, NoSectionError, NoOptionError, ParseError, ShIdentifierError
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*(): void
│   ├── e2e.sh                   # end-to-end tests: runs the script with loup run
│   └── fixtures/app.ini         # sample configuration
├── specs/crudini/               # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup` and `loup-bootstrap` on `PATH`), `make`
and `bash`.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="--get tests/fixtures/app.ini database"` | `loup run bin/crudini.lpscr -- ARGS` |
| Run directly | `./bin/crudini.lpscr -- --get FILE SECTION` | every option is long, so all go after `--` |
| Type-check | `make check` | `loup-bootstrap check FILE` for `bin/crudini.lpscr` and the modules it imports |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn; files go under `build/tmp/` |
| One test file | `make test TESTS=tests/editor_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter merge"` | tests whose name contains `merge` |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: output, files and exit status of `loup run` |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `build/` and `.temp/` |

Run `make ci` before reporting a change as done. Unit tests run under Stage0
(`loup-bootstrap`); the script runs under the self-hosted `loup run`, which
behaves differently in places (below), so only `make e2e` shows what users get.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- A script entry cannot be built (`E-BUILD-COMPILED`), so there is no build
  target. `loup-bootstrap check FILE` does type-check a script and its
  imports; `[build] entry` points at `bin/crudini.lpscr`.
- `loup run SCRIPT --long` treats `--long` as its own flag; the self-hosted
  driver drops it silently. crudini's options are all long: they go after
  `--` (`loup run bin/crudini.lpscr -- --get app.ini`).
- The self-hosted `loup run` cannot catch `IoError`; check `exists`/`isDir`
  before reading (`read_problem`).
- Stage0 (the unit tests) assigns the class FIELD when a method assigns a
  local `var` with the same name. Do not name method locals like fields.
- A struct field cannot hold a union (`E_STRUCT_CLASS_FIELD`): `OptionSpec`
  is a class. A union is passed to `Any` with `box v`.
- `x in xs`, `?.`, interpolation filters and `"""` strings do not work under
  the self-hosted `loup run`; lists have no `insert` (slice and `+`).
- A test that reads `obj!{field}` on a type it does not import directly gets
  `E_DYNAMIC_ACCESS_NOT_DYNAMIC`: import the class (`Section`) in the test.
- `loup-bootstrap test` with all files at once fails random tests with an
  empty `RuntimeError` on a busy machine; the Makefile runs one file at a
  time with `--no-parallel`.

## Making a change

1. Update the spec in `specs/crudini/` (see [specs/README.md](specs/README.md)).
2. Change the code: behaviour in `lib/`, top-level flow in `bin/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh` (edits are
   checked as `diff tests/fixtures/app.ini RESULT`).
4. Run `make ci`.
5. Tick the finished tasks in `specs/crudini/tasks.md`.

Keep behaviour in classes and functions that return values (the `Editor`
collects `--get` output, the document renders lines), so unit tests can
check it; only `bin/crudini.lpscr` prints, reads files and calls `exit`.

## Conventions

- `bin/crudini.lpscr` is `@mode(host.scripted)` with a
  `#!/usr/bin/env -S loup run` line and the executable bit.
- `lib/*.lpscr` are `@mode(host.scripted)`: they use sets, unions matched by
  type and `Any`, which only the interpreters run. `lib/appinfo.loup` and
  `lib/usage.loup` are `host.dual` and hold nothing a native build lacks.
- Imports are relative: `from ..lib.options import (...)` in `bin/` and
  `tests/`, `from .entry import (...)` inside `lib/`.
- A method that changes `this` is `modifier`, and callers wrap the call in
  `safe { ... }`; a function that changes a parameter declares it `edits`.
- Error messages are `crudini: MESSAGE` on standard error; every failure
  exits with status 1, as crudini does.
- Keep `APP_VERSION` in `lib/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
