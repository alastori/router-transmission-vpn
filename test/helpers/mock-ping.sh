#!/bin/sh
# Mock ping — controlled via /tmp/ping_mode
MODE="success"
[ -f /tmp/ping_mode ] && MODE=$(cat /tmp/ping_mode)

case "$MODE" in
  success) exit 0 ;;
  fail)    exit 1 ;;
  *)       exit 0 ;;
esac
