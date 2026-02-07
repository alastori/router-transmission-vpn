#!/bin/sh
# Mock crontab — reads from /tmp/test_crontab
case "$1" in
  -l) cat /tmp/test_crontab 2>/dev/null ;;
esac
