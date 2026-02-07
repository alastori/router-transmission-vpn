#!/bin/sh
# Hybrid transmission-remote: fixture override when /tmp/tr_override_mode exists,
# otherwise delegates to the real binary.
REAL="/usr/bin/transmission-remote-real"
MODE_FILE="/tmp/tr_override_mode"

if [ -f "$MODE_FILE" ]; then
  MODE=$(cat "$MODE_FILE")
  case "$*" in
    *--list*)
      FIXTURE="/opt/test/fixtures/transmission-remote/list-${MODE}.txt"
      [ -f "$FIXTURE" ] && cat "$FIXTURE" && exit 0
      ;;
    *--session-stats*)
      FIXTURE="/opt/test/fixtures/transmission-remote/session-stats-${MODE}.txt"
      [ -f "$FIXTURE" ] && cat "$FIXTURE" && exit 0
      ;;
  esac
fi

exec "$REAL" "$@"
