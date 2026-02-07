#!/usr/bin/env bats
# Tests for /etc/transmission-subtitles.sh and /etc/transmission/oshash.lua
# Exercises: config handling, video discovery, embedded sub detection,
# hash computation, API search/download flow, error handling.

load '../helpers/setup'

SCRIPT="/etc/transmission-subtitles.sh"
OSHASH="/etc/transmission/oshash.lua"
MOCK_BIN="/tmp/mock-subs-bin"
TORRENT_DIR="/tmp/test-torrents"
CONF="/etc/transmission/opensubtitles.conf"

# ── Test setup/teardown ──────────────────────────────────────────────

setup() {
  clean_state
  rm -rf "$MOCK_BIN" "$TORRENT_DIR"
  rm -f "$CONF" /tmp/opensubtitles-token /tmp/opensubtitles-token-expiry
  mkdir -p "$MOCK_BIN" "$TORRENT_DIR"

  # Install mock curl that records calls and returns configurable responses
  cat > "$MOCK_BIN/curl" <<'MOCKCURL'
#!/bin/sh
# Mock curl — logs calls, returns responses based on /tmp/curl_mode
echo "$@" >> /tmp/curl_calls

MODE=$(cat /tmp/curl_mode 2>/dev/null || echo "default")

case "$MODE" in
  login-ok)
    printf '{"token":"test-jwt-token"}\n200'
    ;;
  search-hash-hit)
    # Check if this is a login call
    case "$@" in
      *login*)
        printf '{"token":"test-jwt-token"}\n200'
        ;;
      *download*)
        printf '{"link":"http://dl.example.com/sub.srt","remaining":99}\n200'
        ;;
      *moviehash*)
        printf '{"data":[{"attributes":{"files":[{"file_id":12345}]}}]}\n200'
        ;;
      *)
        printf '\n200'
        ;;
    esac
    ;;
  search-hash-miss-name-hit)
    case "$@" in
      *login*)
        printf '{"token":"test-jwt-token"}\n200'
        ;;
      *download*)
        printf '{"link":"http://dl.example.com/sub.srt","remaining":99}\n200'
        ;;
      *moviehash*)
        printf '{"data":[]}\n200'
        ;;
      *query=*)
        printf '{"data":[{"attributes":{"files":[{"file_id":67890}]}}]}\n200'
        ;;
      *)
        printf '\n200'
        ;;
    esac
    ;;
  search-both-miss)
    case "$@" in
      *login*)
        printf '{"token":"test-jwt-token"}\n200'
        ;;
      *moviehash*|*query=*)
        printf '{"data":[]}\n200'
        ;;
      *)
        printf '\n200'
        ;;
    esac
    ;;
  download-srt)
    # Final download of the actual .srt file (no -w flag in this call)
    printf 'fake subtitle content'
    ;;
  *)
    printf '\n200'
    ;;
esac
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  # Install mock jsonfilter
  cat > "$MOCK_BIN/jsonfilter" <<'MOCKJF'
#!/bin/sh
# Mock jsonfilter — parses expression and returns value from stdin
# Supports: @.token, @.data[0].attributes.files[0].file_id, @.link, @.remaining
INPUT=$(cat)
EXPR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) EXPR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

case "$EXPR" in
  '@.token')
    echo "$INPUT" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
    ;;
  '@.data[0].attributes.files[0].file_id')
    # Return file_id if data array is non-empty
    if echo "$INPUT" | grep -q '"file_id"'; then
      echo "$INPUT" | sed -n 's/.*"file_id":\([0-9]*\).*/\1/p'
    fi
    ;;
  '@.link')
    echo "$INPUT" | sed -n 's/.*"link":"\([^"]*\)".*/\1/p'
    ;;
  '@.remaining')
    echo "$INPUT" | sed -n 's/.*"remaining":\([0-9]*\).*/\1/p'
    ;;
esac
MOCKJF
  chmod +x "$MOCK_BIN/jsonfilter"

  # Default config
  cat > "$CONF" <<'CONF_EOF'
OS_API_KEY="test-api-key"
OS_USER="testuser"
OS_PASS="testpass"
OS_LANG="en"
OS_DOWNLOAD_SUBS="yes"
OS_DETECT_EMBEDDED="yes"
CONF_EOF

  # Put mock bin first in PATH so our mocks shadow real tools
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$MOCK_BIN" "$TORRENT_DIR"
  rm -f "$CONF" /tmp/opensubtitles-token /tmp/opensubtitles-token-expiry
  rm -f /tmp/curl_calls /tmp/curl_mode
}

# ── Helper: create a test video file of known size ───────────────────

create_test_video() {
  local path="$1"
  local size="${2:-131072}"  # default 128KB (minimum for oshash)
  mkdir -p "$(dirname "$path")"
  dd if=/dev/urandom of="$path" bs=1 count="$size" 2>/dev/null
}

# ── 1. oshash: known test vector ─────────────────────────────────────

@test "oshash: computes correct hash for known file" {
  # Create a 128KB file filled with zeros — known hash
  local testfile="/tmp/oshash-test"
  dd if=/dev/zero of="$testfile" bs=1024 count=128 2>/dev/null

  run lua "$OSHASH" "$testfile"
  assert_success
  # 128KB of zeros: filesize=131072 (0x20000), all words are 0
  # hash = filesize only = 0x0000000000020000
  assert_output "0000000000020000"

  rm -f "$testfile"
}

@test "oshash: rejects file smaller than 64KB" {
  local testfile="/tmp/oshash-small"
  dd if=/dev/zero of="$testfile" bs=1 count=100 2>/dev/null

  run lua "$OSHASH" "$testfile"
  assert_failure

  rm -f "$testfile"
}

@test "oshash: rejects missing file" {
  run lua "$OSHASH" "/nonexistent/file.mkv"
  assert_failure
}

# ── 2. Config handling ───────────────────────────────────────────────

@test "subtitles: missing config — exits gracefully" {
  rm -f "$CONF"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="test.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Config not found"
}

@test "subtitles: OS_DOWNLOAD_SUBS=no — exits immediately" {
  sed -i 's/OS_DOWNLOAD_SUBS="yes"/OS_DOWNLOAD_SUBS="no"/' "$CONF"

  create_test_video "$TORRENT_DIR/test.mkv"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="test.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "disabled"
  # Should not have made any curl calls
  [ ! -f /tmp/curl_calls ]
}

@test "subtitles: unconfigured API key — exits gracefully" {
  sed -i 's/OS_API_KEY="test-api-key"/OS_API_KEY="your_api_key_here"/' "$CONF"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="test.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "API key not configured"
}

# ── 3. Video file discovery ──────────────────────────────────────────

@test "subtitles: single video file torrent" {
  create_test_video "$TORRENT_DIR/Movie.mkv"
  echo "search-both-miss" > /tmp/curl_mode

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Processing torrent: Movie.mkv"
  assert_log_contains "No subtitles found"
}

@test "subtitles: directory torrent with multiple videos" {
  mkdir -p "$TORRENT_DIR/ShowS01"
  create_test_video "$TORRENT_DIR/ShowS01/s01e01.mkv"
  create_test_video "$TORRENT_DIR/ShowS01/s01e02.mp4"
  echo "search-both-miss" > /tmp/curl_mode

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="ShowS01" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "No subtitles found for: s01e01.mkv"
  assert_log_contains "No subtitles found for: s01e02.mp4"
}

@test "subtitles: non-video file torrent — no processing" {
  echo "data" > "$TORRENT_DIR/readme.txt"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="readme.txt" \
    run "$SCRIPT"
  assert_success
  # No "Searching" or "No subtitles found" since there are no video files
  refute_log_contains "Searching"
}

# ── 4. Skip existing .srt ───────────────────────────────────────────

@test "subtitles: existing .srt — skips download" {
  create_test_video "$TORRENT_DIR/Movie.mkv"
  echo "already have subs" > "$TORRENT_DIR/Movie.en.srt"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Subtitle already exists"
  # No curl calls (no API interaction)
  [ ! -f /tmp/curl_calls ]
}

# ── 5. Embedded subtitle detection ──────────────────────────────────

@test "subtitles: ffprobe detects embedded English subs — skips download" {
  create_test_video "$TORRENT_DIR/Movie.mkv"

  # Install mock ffprobe that reports English subs
  cat > "$MOCK_BIN/ffprobe" <<'EOF'
#!/bin/sh
echo "eng"
EOF
  chmod +x "$MOCK_BIN/ffprobe"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Embedded English subtitles found"
  [ ! -f /tmp/curl_calls ]
}

@test "subtitles: no ffprobe — graceful degradation, proceeds to download" {
  create_test_video "$TORRENT_DIR/Movie.mkv"
  # Ensure no ffprobe on PATH
  rm -f "$MOCK_BIN/ffprobe"
  echo "search-both-miss" > /tmp/curl_mode

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  # Should not mention embedded subs, should proceed to search
  refute_log_contains "Embedded English"
  assert_log_contains "Searching"
}

@test "subtitles: OS_DETECT_EMBEDDED=no — skips ffprobe check" {
  create_test_video "$TORRENT_DIR/Movie.mkv"
  sed -i 's/OS_DETECT_EMBEDDED="yes"/OS_DETECT_EMBEDDED="no"/' "$CONF"

  # Install ffprobe that would detect subs (should not be called)
  cat > "$MOCK_BIN/ffprobe" <<'EOF'
#!/bin/sh
echo "eng"
EOF
  chmod +x "$MOCK_BIN/ffprobe"
  echo "search-both-miss" > /tmp/curl_mode

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  refute_log_contains "Embedded English"
  assert_log_contains "Searching"
}

# ── 6. Hash search → download ───────────────────────────────────────

@test "subtitles: hash search returns results — downloads subtitle" {
  create_test_video "$TORRENT_DIR/Movie.mkv"

  # Multi-stage mock: curl behaves differently per call
  # We use a wrapper that tracks call count
  cat > "$MOCK_BIN/curl" <<'MCURL'
#!/bin/sh
echo "$@" >> /tmp/curl_calls

# Parse -o flag for file output
OUT_FILE=""
ARGS="$@"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# If -o flag present, this is a file download
if [ -n "$OUT_FILE" ]; then
  printf 'fake subtitle content' > "$OUT_FILE"
  exit 0
fi

case "$ARGS" in
  *login*)
    printf '{"token":"test-jwt-token"}\n200'
    ;;
  *moviehash*)
    printf '{"data":[{"attributes":{"files":[{"file_id":12345}]}}]}\n200'
    ;;
  */download*)
    printf '{"link":"http://dl.example.com/sub.srt","remaining":99}\n200'
    ;;
  *)
    printf '\n200'
    ;;
esac
MCURL
  chmod +x "$MOCK_BIN/curl"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Searching by hash"
  assert_log_contains "Downloading subtitle"
  assert_log_contains "Saved subtitle"

  # Verify .srt was created
  [ -f "$TORRENT_DIR/Movie.en.srt" ]
}

# ── 7. Hash miss → name search fallback ──────────────────────────────

@test "subtitles: hash miss, name hit — downloads via fallback" {
  create_test_video "$TORRENT_DIR/Movie.mkv"

  cat > "$MOCK_BIN/curl" <<'MCURL'
#!/bin/sh
echo "$@" >> /tmp/curl_calls

# Parse -o flag for file output
OUT_FILE=""
ARGS="$@"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# If -o flag present, this is a file download
if [ -n "$OUT_FILE" ]; then
  printf 'fake subtitle content' > "$OUT_FILE"
  exit 0
fi

case "$ARGS" in
  *login*)
    printf '{"token":"test-jwt-token"}\n200'
    ;;
  *moviehash*)
    printf '{"data":[]}\n200'
    ;;
  *query=*)
    printf '{"data":[{"attributes":{"files":[{"file_id":67890}]}}]}\n200'
    ;;
  */download*)
    printf '{"link":"http://dl.example.com/sub.srt","remaining":98}\n200'
    ;;
  *)
    printf '\n200'
    ;;
esac
MCURL
  chmod +x "$MOCK_BIN/curl"

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Searching by hash"
  assert_log_contains "Searching by name"
  assert_log_contains "Saved subtitle"

  [ -f "$TORRENT_DIR/Movie.en.srt" ]
}

# ── 8. Both searches empty → no subtitles found ─────────────────────

@test "subtitles: no results from hash or name search — logs not found" {
  create_test_video "$TORRENT_DIR/Movie.mkv"
  echo "search-both-miss" > /tmp/curl_mode

  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="Movie.mkv" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "No subtitles found for: Movie.mkv"
}

# ── 9. Torrent path not found ───────────────────────────────────────

@test "subtitles: torrent path does not exist — logs and exits" {
  TR_TORRENT_DIR="$TORRENT_DIR" TR_TORRENT_NAME="nonexistent" \
    run "$SCRIPT"
  assert_success
  assert_log_contains "Torrent path not found"
}
