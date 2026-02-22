#!/usr/bin/env bats
# Tests for /etc/transmission/on-complete.sh
# Exercises: file copy, directory copy, missing source, missing Movies dir.

load '../helpers/setup'

ON_COMPLETE="/etc/transmission/on-complete.sh"
MOVIES="/tmp/mountd/disk1_part1/Movies"

setup() {
  clean_state
  mkdir -p "$MOVIES"
  mkdir -p /tmp/transmission
}

teardown() {
  rm -rf /tmp/mountd /tmp/transmission
}

# ── 1. Single file torrent → copies to Movies ─────────────────────

@test "on-complete: single file — copies to Movies" {
  echo "test content" > /tmp/transmission/movie.mkv

  TR_TORRENT_DIR="/tmp/transmission" \
  TR_TORRENT_NAME="movie.mkv" \
  TR_TORRENT_ID="1" \
  run "$ON_COMPLETE"
  assert_success

  [ -f "$MOVIES/movie.mkv" ]
  assert_log_contains "Copied file"
}

# ── 2. Directory torrent → copies folder to Movies ────────────────

@test "on-complete: directory — copies folder to Movies" {
  mkdir -p /tmp/transmission/My.Movie.2025
  echo "video" > /tmp/transmission/My.Movie.2025/video.mkv
  echo "subs" > /tmp/transmission/My.Movie.2025/subs.srt

  TR_TORRENT_DIR="/tmp/transmission" \
  TR_TORRENT_NAME="My.Movie.2025" \
  TR_TORRENT_ID="2" \
  run "$ON_COMPLETE"
  assert_success

  [ -d "$MOVIES/My.Movie.2025" ]
  [ -f "$MOVIES/My.Movie.2025/video.mkv" ]
  assert_log_contains "Copied folder"
}

# ── 3. Source not found → logs error ──────────────────────────────

@test "on-complete: missing source — logs error" {
  TR_TORRENT_DIR="/tmp/transmission" \
  TR_TORRENT_NAME="nonexistent.mkv" \
  TR_TORRENT_ID="3" \
  run "$ON_COMPLETE"
  assert_success

  assert_log_contains "ERROR: source not found"
}

# ── 4. Movies directory missing → logs error and exits ────────────

@test "on-complete: Movies dir missing — logs error" {
  rm -rf "$MOVIES"
  echo "content" > /tmp/transmission/test.mkv

  TR_TORRENT_DIR="/tmp/transmission" \
  TR_TORRENT_NAME="test.mkv" \
  TR_TORRENT_ID="4" \
  run "$ON_COMPLETE"
  assert_failure

  assert_log_contains "Movies directory not found"
}

# ── 5. Filename with spaces → copies correctly ───────────────────

@test "on-complete: filename with spaces — copies correctly" {
  echo "content" > "/tmp/transmission/My Movie (2025).mkv"

  TR_TORRENT_DIR="/tmp/transmission" \
  TR_TORRENT_NAME="My Movie (2025).mkv" \
  TR_TORRENT_ID="5" \
  run "$ON_COMPLETE"
  assert_success

  [ -f "$MOVIES/My Movie (2025).mkv" ]
}
