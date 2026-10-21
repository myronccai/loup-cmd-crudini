#!/usr/bin/env bash
# End-to-end tests: run crudini with `loup run` and compare its standard
# output, standard error, the files it writes and its exit status with the
# expected ones. Edits run on copies of tests/fixtures/app.ini in a
# temporary directory; their result is checked as `diff FIXTURE RESULT`.
#
# usage: tests/e2e.sh [LOUP]     (run from the repository root)

set -u
LOUP=${1:-loup}
SCRIPT=$PWD/bin/crudini.lpscr
FIXTURE=$PWD/tests/fixtures/app.ini
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
INI=$TMP/app.ini
pass=0
fail=0

# run ARGS...: crudini with ARGS after `--` (its options are long options),
# standard input from the file named by $IN (default /dev/null), output to
# $TMP/out and $TMP/err. Returns its exit status.
run() {
    "$LOUP" run "$SCRIPT" -- "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
}

report() {
    local name=$1 status=$2 want_status=$3 want_file=$4 got_file=$5
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$got_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff "$want_file" "$got_file" | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT ARGS...
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/out"
}

# check_err NAME STATUS EXPECTED_STDERR ARGS...
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/err"
}

# edit NAME STATUS EXPECTED_DIFF ARGS...: run ARGS on a fresh copy of the
# fixture ($INI) and compare `diff FIXTURE RESULT`.
edit() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    cp "$FIXTURE" "$INI"
    run "$@"
    local status=$?
    diff "$FIXTURE" "$INI" > "$TMP/got"
    report "$name" $status "$want_status" "$TMP/want" "$TMP/got"
}

# check_file NAME EXPECTED_TEXT FILE: compare a file's contents.
check_file() {
    printf '%s' "$2" > "$TMP/want"
    report "$1" 0 0 "$TMP/want" "$3"
}

# --- --get ------------------------------------------------------------------

check "sections" 0 'DEFAULT
database
server
mysqld
motd
' --get "$FIXTURE"
check "names" 0 $'host\nport\nuser\noptions\n' --get "$FIXTURE" database
check "value" 0 $'db.internal\n' --get "$FIXTURE" database host
check "case-insensitive name" 0 $'5432\n' --get "$FIXTURE" database PORT
check "value with = in it" 0 $'sslmode=require,connect_timeout=10\n' --get "$FIXTURE" database options
check "colon delimiter" 0 $'0.0.0.0:8080\n' --get "$FIXTURE" server listen
check "inherited" 0 $'info\n' --get "$FIXTURE" server log_level
check "global" 0 $'/var/lib/app\n' --get "$FIXTURE" "" data_dir
check "bare name" 0 $'\n' --get "$FIXTURE" mysqld skip-name-resolve
check "multi-line" 0 $'Welcome to the system.\nMaintenance window: Sunday 02:00.\n' --get "$FIXTURE" motd text
check "two gets" 0 $'4\napp\n' --get "$FIXTURE" server workers --get "$FIXTURE" database user
IN=$FIXTURE check "standard input" 0 $'4\n' --get - server workers

check "format ini" 0 '[server]
listen = 0.0.0.0:8080
workers = 4
plugins = auth, metrics
' --format=ini --get "$FIXTURE" server
check "format ini, whole file" 0 $'[DEFAULT]\n[database]\n[server]\n[mysqld]\n[motd]\n' --format ini --get "$FIXTURE"
check "format ini nospace" 0 $'workers=4\n' --format=ini --ini-options=nospace --get "$FIXTURE" server workers
check "format lines" 0 '[ mysqld ] skip-name-resolve
[ mysqld ] max_connections = 200
[ motd ] text = Welcome to the system.\nMaintenance window: Sunday 02:00.
' --format=lines --get "$FIXTURE" mysqld --get "$FIXTURE" motd
check "format sh" 0 "host=db.internal
port=5432
user=app
options=sslmode=require,connect_timeout=10
plugins='auth, metrics'
" --format=sh --get "$FIXTURE" database --get "$FIXTURE" server plugins
check "format sh, whole file, up to a bad name" 1 "log_level=info
data_dir=/var/lib/app
database_host=db.internal
database_port=5432
database_user=app
database_options=sslmode=require,connect_timeout=10
server_listen=0.0.0.0:8080
server_workers=4
server_plugins='auth, metrics'
" --format=sh --get "$FIXTURE"
check_err "format sh, bad name" 1 $'crudini: Invalid sh identifier "mysqld_skip-name-resolve"\n' --format=sh --get "$FIXTURE"

check_err "missing section" 1 $'crudini: Section not found: cache\n' --get "$FIXTURE" cache
check_err "missing parameter" 1 $'crudini: Parameter not found: password\n' --get "$FIXTURE" database password
check_err "missing file" 1 $'crudini: nope.ini: No such file or directory\n' --get nope.ini
check_err "directory" 1 $'crudini: tests: Is a directory\n' --get tests
printf '[a]\nx = 1\n[b\n' > "$TMP/broken.ini"
check_err "parse error" 1 "crudini: $TMP/broken.ini:3: cannot parse '[b'
" --get "$TMP/broken.ini"
printf '[a]\n  x = 1\n' > "$TMP/indented.ini"
check_err "indented parameter" 1 "crudini: $TMP/indented.ini:2: cannot parse '  x = 1' (an indented line continues the value above it; --ini-options=ignoreindent allows indented parameters)
" --get "$TMP/indented.ini"
check "ignoreindent" 0 $'1\n' --ini-options=ignoreindent --get "$TMP/indented.ini" a x

# --- --set --------------------------------------------------------------------

edit "change a value, keep the comment" 0 '6c6
< host = db.internal   ; primary server
---
> host = db.example.com ; primary server
' --set "$INI" database host db.example.com
edit "add a parameter" 0 '9a10
> password = s3cret
' --set "$INI" database password s3cret
edit "add a section" 0 '22a23,25
> 
> [cache]
> size = 64
' --set "$INI" cache size 64
edit "global parameter" 0 '3a4
> pid_file = /run/app.pid
' --set "$INI" "" pid_file /run/app.pid
edit "explicit DEFAULT" 0 '0a1
> [DEFAULT]
2c3
< log_level = info
---
> log_level = debug
' --set "$INI" DEFAULT log_level debug
edit "bare name stays bare" 0 '18a19
> skip-networking
' --set "$INI" mysqld skip-networking --set "$INI" mysqld skip-name-resolve
edit "multi-line value" 0 '13a14
>         # four per core
' --set "$INI" server workers $'4\n# four per core'
edit "several operations" 0 '7c7
< port = 5432
---
> port = 6432
14a15
> timeout = 30
' --set "$INI" database port 6432 --set "$INI" server timeout 30
edit "nospace" 0 '2,3c2,3
< log_level = info
< data_dir = /var/lib/app
---
> log_level=info
> data_dir=/var/lib/app
6,9c6,10
< host = db.internal   ; primary server
< port = 5432
< user = app
< options = sslmode=require,connect_timeout=10
---
> host=db.internal   ; primary server
> port=5432
> user=app
> options=sslmode=require,connect_timeout=10
> ssl=on
12,14c13,15
< listen: 0.0.0.0:8080
< workers = 4
< plugins = auth, metrics
---
> listen:0.0.0.0:8080
> workers=4
> plugins=auth, metrics
18c19
< max_connections = 200
---
> max_connections=200
21c22
< text = Welcome to the system.
---
> text=Welcome to the system.
' --ini-options=nospace --set "$INI" database ssl on
edit "unchanged" 0 '' --set "$INI" server workers 4
edit "sectionspace" 0 '22a23,25
> 
> [new]
> k = v
' --ini-options=sectionspace --set "$INI" new k v

# --- --del --------------------------------------------------------------------

edit "delete a parameter" 0 '8d7
< user = app
' --del "$INI" database user
edit "delete a section" 0 '16,19d15
< [mysqld]
< skip-name-resolve
< max_connections = 200
< 
' --del "$INI" mysqld
edit "delete the global parameters" 0 '2,3d1
< log_level = info
< data_dir = /var/lib/app
' --del "$INI" DEFAULT
edit "delete what is not there" 0 '' --del "$INI" cache size --del "$INI" nosuch

# --- lists ----------------------------------------------------------------------

edit "add to a list" 0 '14c14
< plugins = auth, metrics
---
> plugins = auth, metrics, cache
' --list --set "$INI" server plugins cache
edit "remove from a list" 0 '14c14
< plugins = auth, metrics
---
> plugins = metrics
' --list --del "$INI" server plugins auth
edit "list with a separator" 0 '9c9
< options = sslmode=require,connect_timeout=10
---
> options = sslmode=require,connect_timeout=10,application_name=app
' --list --list-sep=, --set "$INI" database options application_name=app

# --- --merge ----------------------------------------------------------------------

printf 'log_level = warn\n[server]\nworkers = 8\nlog_level = warn\n[cache]\nsize = 64\n' > "$TMP/merge.ini"
IN=$TMP/merge.ini edit "merge" 0 '2c2
< log_level = info
---
> log_level = warn
13c13
< workers = 4
---
> workers = 8
22a23,25
> 
> [cache]
> size = 64
' --merge "$INI"
IN=$TMP/merge.ini edit "merge into one section" 0 '9a10,12
> log_level = warn
> workers = 8
> size = 64
' --merge "$INI" database
printf 'log_level = warn\n[server]\nworkers = 8\nthreads = 2\n' > "$TMP/update.ini"
IN=$TMP/update.ini edit "merge existing only" 0 '2c2
< log_level = info
---
> log_level = warn
13c13
< workers = 4
---
> workers = 8
' --existing=param --merge "$INI" --verbose

# --- --existing -------------------------------------------------------------------

check_err "existing: section" 1 $'crudini: Section not found: cache\n' --existing --set "$INI" cache size 64
check_err "existing: param" 1 $'crudini: Parameter not found: password\n' --existing --set "$INI" database password x
edit "existing=section adds parameters" 0 '9a10
> password = x
' --existing=section --set "$INI" database password x
check_err "existing: file" 1 "crudini: $TMP/new.ini: No such file or directory
" --existing=file --set "$TMP/new.ini" a k v
check_err "existing: del" 1 $'crudini: Section not found: cache\n' --existing --del "$INI" cache

# --- writing ------------------------------------------------------------------------

rm -f "$TMP/new.ini"
check "create a file" 0 '' --set "$TMP/new.ini" first k v
check_file "created contents" $'[first]\nk = v\n' "$TMP/new.ini"
check "del leaves a missing file missing" 0 '' --del "$TMP/absent.ini" first k
[ -e "$TMP/absent.ini" ] && { fail=$((fail + 1)); echo "FAIL: --del created a file"; } || pass=$((pass + 1))
cp "$FIXTURE" "$INI"
chmod 640 "$INI"
check "replace keeps permissions" 0 '' --set "$INI" server workers 2
[ "$(stat -c %a "$INI")" = 640 ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: mode is $(stat -c %a "$INI")"; }
ls "$TMP" | grep -q '\.tmp$' && { fail=$((fail + 1)); echo "FAIL: temporary file left"; } || pass=$((pass + 1))
printf '[a]\nx = 1\n' > "$TMP/target.ini"
ln -sf target.ini "$TMP/link.ini"
check "inplace through a link" 0 '' --inplace --set "$TMP/link.ini" b y 2
check_file "inplace appended" $'[a]\nx = 1\n\n[b]\ny = 2\n' "$TMP/target.ini"
[ -L "$TMP/link.ini" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: --inplace replaced the link"; }
check "output to stdout" 0 $'[a]\nx = 1\n\n[b]\ny = 3\n' --set "$TMP/target.ini" b y 3 --output=-
check_file "input untouched" $'[a]\nx = 1\n\n[b]\ny = 2\n' "$TMP/target.ini"
check "output to a file" 0 '' --del "$TMP/target.ini" a --output "$TMP/copy.ini"
check_file "output file" $'[b]\ny = 2\n' "$TMP/copy.ini"
IN=$TMP/target.ini check "standard input to standard output" 0 $'[a]\nx = 5\n\n[b]\ny = 2\n' --set - a x 5
printf '\357\273\277[a]\r\nx = 1\r\n' > "$TMP/win.ini"
check "byte order mark and CRLF" 0 '' --set "$TMP/win.ini" a y 2
printf '\357\273\277[a]\r\nx = 1\r\ny = 2\r\n' > "$TMP/want.ini"
cmp -s "$TMP/want.ini" "$TMP/win.ini" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: BOM/CRLF"; od -c "$TMP/win.ini" | head -5; }

check_err "verbose: changed" 0 "changed: --set $INI server workers 3
" --verbose --set "$INI" server workers 3
check_err "verbose: unchanged, quoted" 0 "unchanged: --set $INI motd text 'Welcome to the system.\nMaintenance window: Sunday 02:00.'
" --verbose --set "$INI" motd text $'Welcome to the system.\nMaintenance window: Sunday 02:00.'

# --- command line ---------------------------------------------------------------------

HINT="Try 'crudini --help' for more information."
check_err "no operation" 1 "crudini: One of --set|--del|--get|--merge must be specified
$HINT
"
check_err "unknown operation" 1 "crudini: Unknown operation: app.ini
$HINT
" app.ini --get
check_err "unknown option" 1 "crudini: option --colour not recognized
$HINT
" --colour --get "$FIXTURE"
check_err "bad format" 1 "crudini: --format not recognized: json
$HINT
" --format=json --get "$FIXTURE"
check_err "mixed modes" 1 "crudini: --get|--merge modes can't be mixed with --set|--del
$HINT
" --get "$FIXTURE" --set "$FIXTURE" a
check_err "value with --get" 1 "crudini: A value should not be specified with --get
$HINT
" --get "$FIXTURE" a b c
check_err "conflicting DEFAULT" 1 $'crudini: Conflicting DEFAULT section specifications\n' --set "$INI" "" a 1 --set "$INI" DEFAULT b 2
check_err "bad section name" 1 $'crudini: section names should not contain \'[\' or \']\': a]b\n' --set "$INI" 'a]b' k v
check "unique prefix" 0 $'workers = 3\n' --form=ini --get "$INI" server workers
check "version" 0 $'crudini (loup-cmd-crudini) 0.1.0\n' --version
run --help
status=$?
head -1 "$TMP/out" > "$TMP/got"
printf 'usage: crudini --set [OPTION]...   config_file section   [param] [value]\n' > "$TMP/want"
report "help" $status 0 "$TMP/want" "$TMP/got"

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
