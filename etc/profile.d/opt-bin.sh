#!/bin/sh

test ! -d /opt/bin || {
  case "$PATH" in
    *:/opt/bin|/opt/bin:*|*:/opt/bin:*) ;;
    *) export PATH="$PATH:/opt/bin" ;;
  esac
}
