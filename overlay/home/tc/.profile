#!/bin/sh

. /usr/local/lib/tc-ui.sh

# -----------------------------------------------------------------------------
# Network bootstrap
# -----------------------------------------------------------------------------
# iPXE can use a NIC before Linux has configured it. If Tiny Core detects a
# wired interface with carrier but no IPv4 address, quietly request a short
# DHCP lease before presenting the shell. This keeps PXE-booted systems online
# without adding visible startup noise or hanging for long on disconnected NICs.
for IFACE_PATH in /sys/class/net/*; do
    IFACE="$(basename "$IFACE_PATH")"

    [ "$IFACE" = "lo" ] && continue
    [ "$IFACE" = "dummy0" ] && continue

    # Prefer interfaces that currently have physical carrier.
    if [ -r "$IFACE_PATH/carrier" ] && [ "$(cat "$IFACE_PATH/carrier" 2>/dev/null)" != "1" ]; then
        continue
    fi

    IPV4="$(ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([^ ]*\).*/\1/p' | head -n1)"

    if [ -z "$IPV4" ]; then
        sudo udhcpc -q -n -T 2 -t 3 -i "$IFACE" >/dev/null 2>&1 || true
    fi

    # One live wired interface is enough for this lightweight environment.
    break
done

# -----------------------------------------------------------------------------
# Console
# -----------------------------------------------------------------------------

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