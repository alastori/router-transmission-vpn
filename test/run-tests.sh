#!/bin/sh
# Build the test container and run all bats tests.
# Usage: ./test/run-tests.sh
#        ./test/run-tests.sh tests/watchdog.bats        # single file
#        ./test/run-tests.sh -f "stale state"           # single test

set -e
cd "$(dirname "$0")"

echo "Building test container..."
docker compose build --quiet

if [ $# -gt 0 ]; then
  echo "Running: bats $*"
  docker compose run --rm test bats "$@"
else
  echo "Running all tests..."
  docker compose run --rm test
fi
