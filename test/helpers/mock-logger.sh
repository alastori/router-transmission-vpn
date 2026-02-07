#!/bin/sh
# Mock logger — writes to /tmp/test_syslog
TAG="user"
while [ $# -gt 0 ]; do
  case "$1" in
    -t) TAG="$2"; shift 2 ;;
    -p) shift 2 ;;  # ignore priority
    *)  break ;;
  esac
done

echo "$(date '+%b %d %H:%M:%S') $TAG: $*" >> /tmp/test_syslog
