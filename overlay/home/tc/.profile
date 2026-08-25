#!/bin/sh

. /usr/local/lib/tc-ui.sh

# Dynamic login banner sized to the current console.
echo
tc_rule '='
tc_center "TinyCore Tools"
tc_rule '='
echo
tc_center "Lightweight iPXE diagnostic environment"
echo
tc_center "Type 'help' for available commands."
echo

PS1='tc:\w\$ '
export PS1

# ash provides a built-in command named 'help', which takes precedence over
# /usr/local/bin/help. Alias it to the TinyCore Tools help screen instead.
alias help='tc-help'