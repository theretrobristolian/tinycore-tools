#!/bin/sh

# Shared TinyCore Tools console formatting helpers.
# Uses the live terminal width where possible and falls back to 80 columns.

tc_cols() {
    TC_COLS="$(stty size 2>/dev/null | awk '{print $2}')"

    case "$TC_COLS" in
        ''|*[!0-9]*) TC_COLS=80 ;;
    esac

    [ "$TC_COLS" -lt 40 ] && TC_COLS=40
    echo "$TC_COLS"
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
