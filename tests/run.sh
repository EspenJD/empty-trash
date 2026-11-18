#!/usr/bin/env bash
# tests/run.sh [EMPTY_TRASH]: checks of empty-trash on FAKE trash folders in a temporary folder.
# It never deletes in a real trash: EMPTY_TRASH_TEST_DIRS replaces the folder list, and ssh, sudo
# and stat are small stand-ins on PATH where a test needs them. One check lists the real trash,
# read-only. Needs bash and python3 (for the pseudo-terminal in ptyrun.py).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
E=${1:-$here/../empty-trash}
T=$(mktemp -d)/t
export NO_COLOR=1
export STUB_LOG="$T/stub.log"

pty() { python3 "$here/ptyrun.py" "$@" 2>&1; }
pass=0
fail=0
ck() {
  if [[ $2 == "$3" ]]; then
    pass=$((pass + 1))
    echo "ok   $1"
  else
    fail=$((fail + 1))
    echo "FAIL $1 (got $2, want $3)"
  fi
}

# The fake trash folders: two with the macOS layout, three with the FreeDesktop layout.
PARTS=(mac/.Trash vol/.Trashes/501 home/Trash/files home/Trash/info home/Trash/expunged
  mnt/.Trash-1000/files mnt/.Trash-1000/info mnt/.Trash/1000/files)
mk() {
  [[ -d $T ]] && chmod -R u+w "$T" && rm -rf "$T"
  local p
  for p in "${PARTS[@]}" plain target link sym/Trash bin bin2; do mkdir -p "$T/$p"; done
  : > "$STUB_LOG"
  stand_ins
  mkdir -p "$T/mac/.Trash/dir/sub"
  echo x > "$T/mac/.Trash/file1"
  echo x > "$T/mac/.Trash/.hidden"
  echo x > "$T/mac/.Trash/.DS_Store"
  dd if=/dev/zero of="$T/mac/.Trash/dir/sub/big" bs=1024 count=300 2> /dev/null
  ln -s "$T/target" "$T/mac/.Trash/link-item"
  echo x > "$T/mac/keep-outside"
  echo x > "$T/vol/.Trashes/501/v1"
  mkdir -p "$T/home/Trash/files/docs" "$T/home/Trash/expunged/1"
  echo x > "$T/home/Trash/files/a.txt"
  echo x > "$T/home/Trash/files/docs/x"
  dd if=/dev/zero of="$T/home/Trash/files/big.bin" bs=1024 count=200 2> /dev/null
  for p in a.txt docs big.bin; do echo "[Trash Info]" > "$T/home/Trash/info/$p.trashinfo"; done
  echo x > "$T/home/Trash/expunged/1/leftover"
  echo x > "$T/home/Trash/directorysizes"
  echo x > "$T/mnt/.Trash-1000/files/m1"
  echo "[Trash Info]" > "$T/mnt/.Trash-1000/info/m1.trashinfo"
  echo x > "$T/mnt/.Trash/1000/files/s1"
  echo x > "$T/plain/keep-me"         # a folder without a trash name
  echo x > "$T/target/precious"       # reached only through symbolic links
  ln -s "$T/target" "$T/link/.Trash"  # a trash name that is a symbolic link
  ln -s "$T/target" "$T/sym/Trash/files"
}
# ssh runs the worker on this machine. sudo runs the command as the same user. Both write a log.
# They are on PATH for every test, so no test can reach a real host or ask for a password.
stand_ins() {
  cat > "$T/bin/ssh" << 'EOF'
#!/bin/sh
echo "ssh $*" >> "$STUB_LOG"
while [ $# -gt 0 ]; do case $1 in -o) shift 2 ;; --) shift; break ;; *) break ;; esac; done
[ "$1" = deadhost ] && { echo "ssh: connect to host deadhost: timed out" >&2; exit 255; }
eval "$2"
EOF
  cat > "$T/bin/sudo" << 'EOF'
#!/bin/sh
echo "sudo $*" >> "$STUB_LOG"
[ -n "${SUDO_FAIL:-}" ] && exit 1
[ "$1" = -n ] && shift
[ "$1" = -v ] && exit 0
exec "$@"
EOF
  cat > "$T/bin2/stat" << 'EOF'
#!/bin/sh
# Every file has the owner 4242. Other questions go to the real stat.
if [ "$2" = %u ]; then echo 4242; else exec /usr/bin/stat "$@"; fi
EOF
  chmod 755 "$T/bin/ssh" "$T/bin/sudo" "$T/bin2/stat"
}
left() {
  local p n=0
  for p in "${PARTS[@]}"; do
    n=$((n + $(find "$T/$p" -mindepth 1 ! -name .DS_Store | wc -l)))
  done
  echo "$n"
}
safe() { [[ -f $T/plain/keep-me && -f $T/target/precious && -f $T/mac/keep-outside ]] && echo safe; }
export EMPTY_TRASH_TEST_DIRS="$T/mac/.Trash:$T/vol/.Trashes/501:$T/home/Trash:$T/mnt/.Trash-1000:$T/mnt/.Trash/1000:$T/plain:$T/link/.Trash:$T/sym/Trash:$T/missing/.Trash"
export EMPTY_TRASH_HOSTS="$T/no-hosts-file"
PATH="$T/bin:$PATH"

echo "bash: $(bash --version | head -1)"
echo "system: $(uname -sr)"
mk
all=$(left)
ck "setup: the fake trash holds files" "$((all > 10))" 1

echo "--- without a terminal"
out=$(echo y | "$E" local 2>&1)
rc=$?
ck "no terminal: 'y' on stdin deletes nothing" "$(left) rc=$rc" "$all rc=0"
ck "no terminal: the run says that it only lists" "$(grep -c 'only lists' <<< "$out")" 1
ck "list: 5 trash folders, 11 items in total" "$(grep -c ' items\{0,1\}  /' <<< "$out")/$(grep -c 'Total: .*, 11 items' <<< "$out")" "5/1"
ck "list: the biggest item of a folder comes first" "$(grep -A1 'mac/.Trash$' <<< "$out" | tail -1 | awk '{ print $NF }')" dir
ck "list: a folder without a trash name is named and left alone" "$(grep -c "not a trash folder, left alone: $T/plain" <<< "$out")" 1
ck "list: a trash folder that is a symbolic link is left alone" "$(grep -c "a symbolic link, left alone: $T/link/.Trash" <<< "$out")" 1

echo "--- at a terminal"
out=$(pty n "$E" local)
ck "answer n: the prompt came, nothing deleted" "$(grep -c 'prompts=1 rc=0' <<< "$out") $(left)" "1 $all"
out=$(pty '' "$E" local)
ck "answer Enter only: nothing deleted" "$(grep -c 'Left as is' <<< "$out") $(left)" "1 $all"
out=$(pty yes "$E" local)
ck "answer 'yes' (not y): nothing deleted" "$(grep -c 'Left as is' <<< "$out") $(left)" "1 $all"
out=$(pty y "$E" --list local)
ck "--list: no prompt, nothing deleted" "$(grep -c 'prompts=0 rc=0' <<< "$out") $(left)" "1 $all"
out=$(pty y "$E" local)
ck "answer y: every trash folder is empty" "$(left) $(grep -c 'Emptied' <<< "$out") $(grep -c 'rc=0' <<< "$out")" "0 1 1"
ck "answer y: the trash folders themselves stay" \
  "$(for p in "${PARTS[@]}"; do [[ -d $T/$p ]] && printf y; done)" yyyyyyyy
ck "answer y: the size cache of the FreeDesktop trash is gone" "$([[ -e $T/home/Trash/directorysizes ]] || echo gone)" gone
ck "answer y: files outside the trash and behind links stay" "$(safe)" safe
out=$(pty y "$E" local)
ck "second run: the trash is empty, no prompt" "$(grep -c 'The trash is empty' <<< "$out")/$(grep -c 'prompts=0 rc=0' <<< "$out")" "1/1"

if ((EUID != 0)); then
  mk
  mkdir "$T/mac/.Trash/stuck"
  echo x > "$T/mac/.Trash/stuck/f"
  chmod 555 "$T/mac/.Trash/stuck"
  out=$(pty y "$E" local)
  ck "an item that cannot be deleted is reported, exit code 1" \
    "$(grep -c 'Still there: 1 item ' <<< "$out")/$(grep -c 'rc=1' <<< "$out")" "1/1"
  chmod 755 "$T/mac/.Trash/stuck"
fi

echo "--- options"
mk
"$E" --bogus > /dev/null 2>&1
ck "an unknown option: exit code 2" "$?" 2
"$E" 'bad;name' > /dev/null 2>&1
ck "a target that is not a host name: exit code 2" "$?" 2
ck "--help shows the usage" "$("$E" --help | grep -c '^Usage: empty-trash')" 1
ck "--version shows a version" "$("$E" --version | grep -c '^empty-trash [0-9]')" 1
"$E" __worker empty > /dev/null 2>&1
ck "the internal worker mode is refused for the command file" "$? $(left)" "2 $all"
ck "there is no --yes option" "$("$E" --yes local > /dev/null 2>&1; echo $?) $(left)" "2 $all"

echo "--- another host (ssh is a stand-in that runs the worker here)"
out=$("$E" myhost 2>&1 < /dev/null)
ck "host, no terminal: list only" "$(grep -c '^myhost:' <<< "$out")/$(grep -c 'Total: .*, 11 items' <<< "$out") $(left)" "1/1 $all"
ck "host, no terminal: ssh may not ask for a password" "$(grep -c 'BatchMode=yes -- myhost bash -s -- __worker list' "$STUB_LOG")" 1
out=$(pty n "$E" myhost)
ck "host, answer n: nothing deleted" "$(grep -c 'Left as is' <<< "$out") $(left)" "1 $all"
out=$(pty y "$E" myhost)
ck "host, answer y: the trash there is empty" "$(left) $(grep -c 'Emptied' <<< "$out") $(grep -c -- '-- myhost bash -s -- __worker empty' "$STUB_LOG")" "0 1 1"
ck "host, answer y: files outside the trash and behind links stay" "$(safe)" safe
out=$("$E" --list deadhost 2>&1)
rc=$?
ck "host that does not answer: a clear line, exit code 1" "$(grep -c 'no answer from deadhost' <<< "$out") rc=$rc" "1 rc=1"

echo "--- hosts file and sudo"
mk
printf '# my machines\nmyhost\n\nother sudo\nbad;name\n' > "$T/hosts"
out=$(EMPTY_TRASH_HOSTS="$T/hosts" "$E" --list 2>&1)
ck "no target: this machine, then the hosts in the file" "$(grep -E '^(This machine|myhost|other):' <<< "$out" | tr -d '\n')" "This machine:myhost:other:"
ck "hosts file: 'sudo' after a host reaches the worker" "$(grep -c -- '-- other bash -s -- __worker list sudo' "$STUB_LOG")/$(grep -c -- '-- myhost bash -s -- __worker list $' "$STUB_LOG")" "1/1"
ck "hosts file: a line that is not a host name is named and skipped" "$(grep -c 'not a host name' <<< "$out")" 1
printf 'myhost\nother sudo' > "$T/hosts-no-line-end"
: > "$STUB_LOG"
EMPTY_TRASH_HOSTS="$T/hosts-no-line-end" "$E" --list > /dev/null 2>&1
ck "hosts file: a last line without a line end is read" "$(grep -c -- '-- other bash -s -- __worker list sudo' "$STUB_LOG")" 1

# A host that is named as a target takes its word "sudo" from the hosts file.
: > "$STUB_LOG"
out=$(EMPTY_TRASH_HOSTS="$T/hosts" "$E" --list other 2>&1)
ck "named host with 'sudo' in the hosts file: 'sudo' reaches the worker" "$(grep -c -- '-- other bash -s -- __worker list sudo' "$STUB_LOG")" 1
ck "named host: a bad line in the hosts file is not named" "$(grep -c 'not a host name' <<< "$out")" 0
: > "$STUB_LOG"
EMPTY_TRASH_HOSTS="$T/hosts" "$E" --list myhost > /dev/null 2>&1
ck "named host without the word in the hosts file: no sudo" "$(grep -c -- '-- myhost bash -s -- __worker list $' "$STUB_LOG")/$(grep -c '^sudo ' "$STUB_LOG")" "1/0"
: > "$STUB_LOG"
EMPTY_TRASH_HOSTS="$T/hosts" "$E" --list nothere > /dev/null 2>&1
ck "named host that is not in the hosts file: no sudo" "$(grep -c -- '-- nothere bash -s -- __worker list $' "$STUB_LOG")/$(grep -c '^sudo ' "$STUB_LOG")" "1/0"
: > "$STUB_LOG"
EMPTY_TRASH_HOSTS="$T/hosts" "$E" --list --sudo myhost nothere > /dev/null 2>&1
ck "--sudo with named hosts: sudo, whatever the hosts file says" "$(grep -c -- 'bash -s -- __worker list sudo' "$STUB_LOG")" 2
printf 'local sudo\n' > "$T/hosts-local"
: > "$STUB_LOG"
out=$(EMPTY_TRASH_HOSTS="$T/hosts-local" "$E" --list local 2>&1)
ck "target 'local': a line 'local sudo' in the hosts file gives no sudo" "$(grep -c '^This machine:' <<< "$out")/$(grep -c '^sudo ' "$STUB_LOG")" "1/0"
: > "$STUB_LOG"
out=$(EMPTY_TRASH_HOSTS="$T/hosts" pty y "$E" other)
ck "named host with 'sudo' in the hosts file, answer y: the worker deletes through sudo" "$(left) $(grep -c '^sudo -n find .* -exec rm' "$STUB_LOG" | awk '{ print ($1 > 0) }')" "0 1"

mk
out=$(pty y "$E" --sudo local)
ck "--sudo: the worker deletes through sudo" "$(left) $(grep -c '^sudo -n find .* -exec rm' "$STUB_LOG" | awk '{ print ($1 > 0) }')" "0 1"
mk
out=$(SUDO_FAIL=1 "$E" --list --sudo local 2>&1)
rc=$?
ck "--sudo without the right: the run says so, lists, exit code 1" "$(grep -c 'sudo needs a password' <<< "$out")/$(grep -c 'Total: .*, 11 items' <<< "$out") rc=$rc" "1/1 rc=1"

echo "--- a folder of another user"
out=$(PATH="$T/bin2:$PATH" pty y "$E" local)
ck "trash folders of another user are left alone" "$(grep -c 'owned by another user, left alone' <<< "$out") $(left) $(grep -c 'prompts=0' <<< "$out")" "6 $all 1"

echo "--- the real trash, list only"
out=$(env -u EMPTY_TRASH_TEST_DIRS "$E" --list local 2>&1)
rc=$?
ck "real folders: the list runs" "$(grep -c '^This machine:' <<< "$out") $((rc < 2))" "1 1"

chmod -R u+w "$T" && rm -rf "$T"
echo "pass=$pass fail=$fail"
((fail == 0))
