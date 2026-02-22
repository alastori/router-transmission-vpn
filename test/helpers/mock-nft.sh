#!/bin/sh
# Mock nft — returns canned fixture output based on /tmp/nft_mode
# Also records write operations (add, flush, insert) to /tmp/nft_calls for verification.
MODE_FILE="/tmp/nft_mode"
MODE="present"
[ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE")

# Record write operations for test assertions
case "$1" in
  add|flush|insert|delete)
    echo "$*" >> /tmp/nft_calls
    exit 0
    ;;
esac

# Detect which chain is being queried
case "$*" in
  *"transmission_vpn"*)
    case "$MODE" in
      present)
        cat /opt/test/fixtures/nft/chain-clean.txt
        exit 0
        ;;
      present-with-rejects)
        cat /opt/test/fixtures/nft/chain-with-rejects.txt
        exit 0
        ;;
      missing)
        cat /opt/test/fixtures/nft/chain-missing.txt >&2
        exit 1
        ;;
      firewall-fresh)
        # Chain does not exist yet — first run of firewall.user
        echo "Error: No such file or directory; did you mean chain 'output' in table inet 'fw4'?" >&2
        exit 1
        ;;
    esac
    ;;
  *"output"*)
    case "$MODE" in
      no-jump)
        cat /opt/test/fixtures/nft/output-no-jump.txt
        exit 0
        ;;
      *)
        cat /opt/test/fixtures/nft/output-with-jump.txt
        exit 0
        ;;
    esac
    ;;
esac

# Default: success with clean chain
cat /opt/test/fixtures/nft/chain-clean.txt
exit 0
