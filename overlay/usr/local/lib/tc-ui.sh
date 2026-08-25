#!/bin/sh

# Shared TinyCore Tools console formatting helpers.
# Uses the live terminal dimensions where possible and falls back to 80x25.

tc_cols() {
    TC_COLS="$(stty size 2>/dev/null | awk '{print $2}')"
    case "$TC_COLS" in
        ''|*[!0-9]*) TC_COLS=80 ;;
    esac
    [ "$TC_COLS" -lt 40 ] && TC_COLS=40
    echo "$TC_COLS"
}

tc_rows() {
    TC_ROWS="$(stty size 2>/dev/null | awk '{print $1}')"
    case "$TC_ROWS" in
        ''|*[!0-9]*) TC_ROWS=25 ;;
    esac
    [ "$TC_ROWS" -lt 15 ] && TC_ROWS=15
    echo "$TC_ROWS"
}

tc_rule() {
    TC_CHAR="${1:-=}"
    TC_WIDTH="$(tc_cols)"
    printf '%*s\n' "$TC_WIDTH" '' | tr ' ' "$TC_CHAR"
}

tc_center() {
    TC_TEXT="$1"
    TC_WIDTH="$(tc_cols)"
    TC_LEN=${#TC_TEXT}

    if [ "$TC_LEN" -ge "$TC_WIDTH" ]; then
        printf '%s\n' "$TC_TEXT"
        return
    fi

    TC_PAD=$(( (TC_WIDTH - TC_LEN) / 2 ))
    printf '%*s%s\n' "$TC_PAD" '' "$TC_TEXT"
}

tc_pause() {
    tc_center "Press any key to continue..."

    # Read exactly one key without requiring Enter. Restore terminal settings
    # immediately afterwards so the shell remains normal even on old consoles.
    TC_STTY="$(stty -g 2>/dev/null || true)"
    if [ -n "$TC_STTY" ]; then
        stty -echo -icanon min 1 time 0
        dd bs=1 count=1 >/dev/null 2>&1 || true
        stty "$TC_STTY"
    else
        read -r _
    fi
}
