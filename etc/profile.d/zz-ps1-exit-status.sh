#!/bin/sh

_set_prompt_exit_status () { 
  case "$1" in 
      0) _last_exit_status="" ;;
      *) _last_exit_status="$1|" ;;
  esac
  case "$PS1" in
    *_last_exit_status*) ;;
    *) PS1="\$_last_exit_status$PS1"
  esac
}

case "$PROMPT_COMMAND" in
  *_set_prompt_exit_status*) ;;
  *) PROMPT_COMMAND="_set_prompt_exit_status \"\$?\"; $PROMPT_COMMAND"
esac

