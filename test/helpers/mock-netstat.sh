#!/bin/sh
# Mock netstat — shows port 9091 listening if transmission-daemon is running
if pgrep -x transmission-da >/dev/null 2>&1; then
  echo "tcp        0      0 0.0.0.0:9091           0.0.0.0:*               LISTEN"
  echo "tcp        0      0 0.0.0.0:51413          0.0.0.0:*               LISTEN"
else
  echo ""
fi
