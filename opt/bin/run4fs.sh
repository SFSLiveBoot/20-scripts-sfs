#!/bin/sh

: ${schema:=org.gnome.desktop.wm.preferences}
: ${key:=focus-mode}
: ${temp_val:=click}

test -n "$1" || {
  cat >&2 <<EOF

Usage: ${0##*/} <program_with_args..>

Runs a program compatible with gnome-shell full-screen mode, working around the click-through bug
  Cf.: https://bbs.archlinux.org/viewtopic.php?id=192304

EOF
  exit 1
}

val="$(gsettings get $schema $key)"

gsettings set $schema $key $temp_val

"$@"
ret="$?"

gsettings set $schema $key $val
exit $ret
