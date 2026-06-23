#!/usr/bin/env python3

import subprocess, sys, re
from urllib.parse import quote, unquote

proc = subprocess.Popen(
    ["pinentry"], stdout=subprocess.PIPE, stdin=subprocess.PIPE, text=True, bufsize=1
)


def get_pin(match):
    proc.stdin.write("GETPIN\r\n")
    return ["no_pin", "pin", "cancel"]


def set_prompt(match):
    if len(sys.argv) > 1:
        proc.stdin.write(f'SETPROMPT {quote(" ".join(sys.argv[1:]))}\r\n')
        return ["prompt_set"]
    else:
        return get_pin(None)


def exit_ok(match):
    print("")
    proc.stdin.write("BYE\r\n")


def print_pin(match):
    print(unquote(match.group(1)))
    proc.stdin.write("BYE\r\n")


def exit_cancel(match):
    proc.stdin.write("BYE\r\n")
    sys.exit(255)


ok_re = re.compile("^OK ?(.*)")
states = dict(
    START=(None, None, ["hello"]),
    hello=(ok_re, set_prompt, None),
    prompt_set=(ok_re, get_pin, None),
    no_pin=(re.compile(r"^OK$"), exit_ok, None),
    pin=(re.compile(r"^D (.*)"), print_pin, None),
    cancel=(re.compile(r"^ERR (.*)"), exit_cancel, None),
)

state = "START"
input = ""
input_source = proc.stdout

while True:
    _, state_handler, next_states = states[state]
    if state_handler is not None:
        maybe_next_states = state_handler(match)
        if maybe_next_states is not None:
            next_states = maybe_next_states

    input = input + input_source.readline()
    # print(f"Line: {input!r}")

    if next_states is None:
        # print("end processing: no more states")
        break

    for st in next_states:
        match = states[st][0].match(input)
        if match is not None:
            # print(f"matched state: {st}")
            input, state = "", st
            break

proc.wait()
