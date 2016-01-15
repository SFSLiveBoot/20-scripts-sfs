#!/bin/sh

_set_prompt_exit_status () {
  _last_exit_status="$?"
  test ! "$_last_exit_status" = 0 || _last_exit_status=""
  return $_last_exit_status
}

_add_status_to_ps1() {
  local status_var_name="${1:-_last_exit_status}"
  local red="$( (tput setaf 1; tput bold) | sed -e 's/\x1b/\\e/g' )"
  local sgr0="$(tput sgr0 | sed -e 's/\x1b/\\e/g')"
  case "$PS1" in
    *$status_var_name*) ;;
    *) PS1="\${$status_var_name:+\[$red\]\$$status_var_name\[$sgr0\]|}$PS1" ;;
  esac
}

case "$PROMPT_COMMAND" in
  *_set_prompt_exit_status*) ;;
  *)
    _add_status_to_ps1 _last_exit_status
    PROMPT_COMMAND="_set_prompt_exit_status; $PROMPT_COMMAND"
  ;;
esac
