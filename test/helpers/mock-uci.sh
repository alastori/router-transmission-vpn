#!/bin/sh
# Mock uci — key-value store backed by /tmp/uci_store
STORE="/tmp/uci_store"
[ -f "$STORE" ] || touch "$STORE"

QUIET=0
while [ "$1" = "-q" ]; do QUIET=1; shift; done

case "$1" in
  get)
    VALUE=$(grep "^$2=" "$STORE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ -n "$VALUE" ]; then
      echo "$VALUE"
    else
      [ "$QUIET" = 0 ] && echo "uci: Entry not found" >&2
      exit 1
    fi
    ;;
  set)
    KEY="${2%%=*}"; VAL="${2#*=}"
    if grep -q "^$KEY=" "$STORE" 2>/dev/null; then
      sed -i "s|^$KEY=.*|$KEY=$VAL|" "$STORE"
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
