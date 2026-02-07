#!/bin/sh
# Mock /etc/init.d/transmission — manages the real daemon in the test container
case "$1" in
  start)
    pgrep -x transmission-da >/dev/null 2>&1 || \
      transmission-daemon --config-dir /etc/transmission --no-auth --foreground >/dev/null 2>&1 &
    sleep 1
    ;;
  stop)
    pkill -x transmission-da 2>/dev/null
    sleep 1
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  status)
    pgrep -x transmission-da >/dev/null 2>&1 && echo "running" || echo "stopped"
    ;;
esac
