#!/bin/sh

case "$0" in
  *enable*) enable=true;;
  *disable*) enable=false;;
esac

dbus-send --system --dest=org.freedesktop.NetworkManager --type=method_call --print-reply /org/freedesktop/NetworkManager org.freedesktop.NetworkManager.Enable boolean:$enable
