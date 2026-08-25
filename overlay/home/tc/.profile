#!/bin/sh

PS1='tc:\w\$ '
export PS1

# ash provides a built-in command named 'help', which takes precedence over
# /usr/local/bin/help. Alias it to the TinyCore Tools help screen instead.
alias help='tc-help'