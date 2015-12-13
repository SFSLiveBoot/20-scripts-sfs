#!/bin/sh

ssh_host="$1"
test -n "$ssh_host" || {
  echo "Usage: ${0##*/} <ssh_host> [<vncviewer_opts>..]" >&2
  exit 1
}
shift

exec env VNC_VIA_CMD='socat tcp-l:$L,bind=127.0.0.1,reuseaddr,rcvtimeo=20 exec:"ssh -T -e none $G x11vnc -inetd -nopw -display \:0"&' \
  vncviewer -via "$ssh_host" "$ssh_host" "$@"
