# Requirements: crudini

## Introduction

`crudini` reads and changes INI files from the command line, like Pádraig
Brady's [crudini](https://github.com/pixelb/crudini): it prints sections,
parameters and values (`--get`), adds or changes them (`--set`), removes
them (`--del`) and merges another INI file into one (`--merge`). Edits keep
everything they do not touch byte for byte: comments, blank lines, spacing
around `=`, inline comments, line endings and a byte order mark.

It is a host-scripted project of the loup-cmd series: the program is
`bin/crudini.lpscr`, run with `loup run`, over modules in `lib/`.

## Requirements

### Requirement 1: Command line

**User Story:** As an administrator, I want crudini's own command line so
that scripts written for crudini work unchanged.

#### Acceptance Criteria

1. THE program SHALL accept `--set FILE SECTION [PARAM [VALUE]]`,
   `--get FILE [SECTION [PARAM]]`, `--del FILE SECTION [PARAM [LIST-VALUE]]`
   and `--merge FILE [SECTION]`; options and operations may come in any
   order, and the words after an operation are its operands.
2. THE program SHALL accept the options `--existing[=WHAT]`,
   `--format=FMT`, `--ini-options=OPT[,OPT]...`, `--inplace`, `--list`,
   `--list-sep=STR`, `--output=FILE`, `--verbose`, `--help` and
   `--version`; an option that takes a value SHALL also accept it as the next
   word (`--format sh`).
3. WHEN several `--set` and `--del` operations are given, THE program SHALL
   apply them in order to one file; WHEN several `--get` operations are given
   it SHALL print each in order.
4. WHEN `--` is given, THE words after it SHALL be operands of the last
   operation.
5. THE program SHALL reject, with a message and exit status 1: no operation,
   a word before any operation, an unknown option, a missing or unexpected
   option value, a bad `--format`, `--existing` or `--ini-options` value,
   both `space` and `nospace`, mixing `--get`/`--merge` with `--set`/`--del`,
   a second `--merge`, operations on different files, missing operands, a
   value with `--get`/`--merge` (or with `--del` without `--list`), `[` or
   `]` in a section name, a parameter name that starts with `[` or contains
   `=`, `--format=sh` with `--merge`, and `""` and `DEFAULT` used for the
   global section in the same command.
6. `--help` SHALL print the usage on standard output and `--version` SHALL
   print `crudini (loup-cmd-crudini) 0.1.0`, both with status 0.

### Requirement 2: Reading INI files

**User Story:** As an administrator, I want the INI dialects found on real
systems understood so that I can edit them in place.

#### Acceptance Criteria

1. THE reader SHALL recognise section headers `[name]` (optionally followed
   by a `;` or `#` comment), parameters `name = value` and `name: value`
   (the first `=` or `:` separates), parameters without a value (`name`
   alone), comment lines starting with `#`, `;` or `%`, blank lines, and
   continuation lines (indented lines right after a parameter, joined to its
   value with newlines).
2. THE reader SHALL treat ` ;text` after a value as an inline comment and
   keep it when the value changes.
3. Parameters before the first section header, and those under
   `[DEFAULT]`, SHALL form the `DEFAULT` section, which every other section
   inherits from when a value is looked up.
4. Section names SHALL be case-sensitive; parameter names SHALL match
   case-insensitively and keep their spelling.
5. WHEN a section or parameter appears more than once, the occurrences SHALL
   act as one: the last value wins.
6. THE reader SHALL accept a UTF-8 byte order mark and CRLF line endings and
   write them back.
7. WHEN a line is a broken header, a parameter with no name, or an indented
   line that continues nothing, THE program SHALL print
   `crudini: FILE:LINE: cannot parse 'TEXT'` and exit with status 1;
   `--ini-options=ignoreindent` SHALL make leading whitespace insignificant
   instead.

### Requirement 3: --get

**User Story:** As a script author, I want values out of INI files in forms
the shell can use.

#### Acceptance Criteria

1. WITHOUT a section, THE program SHALL list the section names, `DEFAULT`
   first when it has parameters; WITH a section, its parameter names; WITH
   a parameter, its value (inherited from `DEFAULT` when the section lacks
   it).
2. `--format=ini` SHALL print `[section]` headers and `name = value` lines
   (`name=value` with `--ini-options=nospace`), continuation lines indented
   by one space.
3. `--format=lines` SHALL print one `[ section ] name = value` line per
   parameter (`[ section ]` alone for an empty section, newlines in values
   as `\n`).
4. `--format=sh` SHALL print `name=VALUE` lines with VALUE quoted by
   `core.shlex.quote`, prefixing names with `SECTION_` when the whole file is
   listed; WHEN a name is not a valid shell identifier it SHALL print
   `crudini: Invalid sh identifier "NAME"` and exit with status 1.
5. WHEN the section or parameter does not exist, THE program SHALL print
   `crudini: Section not found: S` or `crudini: Parameter not found: P` and
   exit with status 1.
6. WHEN FILE is `-`, THE program SHALL read standard input.

### Requirement 4: --set

**User Story:** As an administrator, I want to add and change settings
without disturbing the rest of the file.

#### Acceptance Criteria

1. THE program SHALL change the value of an existing parameter in place, or
   add the parameter after the last parameter of its section (right after
   the header when it has none).
2. WHEN the section does not exist, THE program SHALL add it at the end of
   the file, after one blank line.
3. WITHOUT a value, THE program SHALL add the parameter with an empty value,
   or as a bare name when the file already has bare names, and leave an
   existing bare name alone.
4. Section `""` SHALL address the global parameters (before any header);
   section `DEFAULT` SHALL do the same but add a `[DEFAULT]` header when
   the file has none.
5. New parameters SHALL be written `name = value`; `--ini-options=nospace`
   SHALL write `name=value` and rewrite every parameter that way, `space`
   SHALL rewrite every parameter as `name = value`.
6. A value with newlines SHALL be written as continuation lines.
7. WHEN FILE does not exist, THE program SHALL create it.

### Requirement 5: --del

**User Story:** As an administrator, I want to remove settings cleanly.

#### Acceptance Criteria

1. WITH a parameter, THE program SHALL remove every occurrence of it from
   the section, continuation lines included.
2. WITHOUT a parameter, THE program SHALL remove the section (all its
   occurrences) and tidy the blank lines left behind; for `DEFAULT` it SHALL
   remove the global parameters and a `[DEFAULT]` header.
3. WHEN what is to be removed does not exist, or FILE does not exist,
   nothing SHALL change.

### Requirement 6: Lists

**User Story:** As an administrator, I want to add or remove one item of a
list value such as `plugins = a, b`.

#### Acceptance Criteria

1. WITH `--list`, `--set` SHALL add VALUE to the list unless it is already
   there, and `--del` SHALL remove it; the list keeps its order.
2. By default items are separated by commas, written `, ` unless the
   existing value uses `,` with no spaces; `--list-sep=STR` SHALL use STR,
   and an empty STR SHALL mean any whitespace (the first run of whitespace
   in the value is kept as the separator).
3. `--list` without a value SHALL empty the list.

### Requirement 7: --merge

**User Story:** As an administrator, I want to apply a fragment of settings
from standard input to a file.

#### Acceptance Criteria

1. THE program SHALL read an INI document from standard input with
   `data.ini` and set each of its parameters in the file, section by section
   (global parameters into `DEFAULT`); WITH a SECTION operand, all of them
   SHALL go into that section.
2. A parameter whose value equals the input's own `DEFAULT` value SHALL be
   skipped, and an input section without parameters SHALL still be added.

### Requirement 8: --existing

**User Story:** As a script author, I want edits to fail when they would
create something, so that typos do not go unnoticed.

#### Acceptance Criteria

1. WITH `--existing` (any WHAT), a missing FILE SHALL be an error.
2. WITH `--existing=section`, a missing section SHALL be an error; WITH
   `--existing` or `--existing=param`, a missing section or parameter SHALL
   be an error (for `--merge`, missing parameters are skipped instead).
3. Errors SHALL be reported as in 3.5, with exit status 1 and the file left
   unchanged.

### Requirement 9: Writing

**User Story:** As an administrator, I want a change to replace the file
safely, or to write it in place when I ask.

#### Acceptance Criteria

1. By default THE program SHALL write the new contents to a temporary file
   next to the target, keeping the target's permission bits, and rename it
   over the target; the temporary file SHALL be removed if anything fails.
2. WITH `--inplace`, THE program SHALL rewrite the file itself, and WHEN the
   change only adds lines at the end and the file still holds exactly what
   was read, it SHALL append them instead.
3. THE program SHALL NOT write the file when its contents do not change.
4. `--output=FILE` SHALL write the result to FILE instead (`-` for standard
   output).
5. `--ini-options=sectionspace` SHALL leave exactly one blank line before
   every section header and none at the start or end of the file.
6. WITH `--verbose`, THE program SHALL print `changed: ...` or
   `unchanged: ...` on standard error, naming the last operation with its
   words quoted for the shell.
