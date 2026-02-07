#!/bin/sh
# Mock uci — key-value store backed by /tmp/uci_store
# Uses grep -F (fixed-string) because uci keys contain regex-special chars like [0]
STORE="/tmp/uci_store"
[ -f "$STORE" ] || touch "$STORE"

QUIET=0
while [ "$1" = "-q" ]; do QUIET=1; shift; done

case "$1" in
  get)
    VALUE=$(grep -F "$2=" "$STORE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ -n "$VALUE" ]; then
      echo "$VALUE"
    else
      [ "$QUIET" = 0 ] && echo "uci: Entry not found" >&2
      exit 1
    fi
    ;;
  set)
    KEY="${2%%=*}"; VAL="${2#*=}"
    if grep -qF "$KEY=" "$STORE" 2>/dev/null; then
      # Use awk for replacement since sed can't handle literal special chars easily
      awk -v key="$KEY" -v val="$VAL" 'BEGIN{FS="="; OFS="="} $1==key{$0=key"="val} {print}' "$STORE" > "${STORE}.tmp"
      mv "${STORE}.tmp" "$STORE"
    else
      echo "$KEY=$VAL" >> "$STORE"
    fi
    ;;
  commit)
    ;; # no-op
  show)
    cat "$STORE" 2>/dev/null
    ;;
esac
