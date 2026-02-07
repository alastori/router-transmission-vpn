#!/bin/sh
# /etc/transmission-subtitles.sh — Download subtitles for completed torrents
# Called by Transmission's script-torrent-done mechanism.
# Searches OpenSubtitles.com by hash first, filename fallback second.
#
# Env vars set by Transmission:
#   TR_TORRENT_DIR  — directory containing the torrent
#   TR_TORRENT_NAME — name of the torrent (file or directory)

TAG="transmission-subtitles"
CONF="/etc/transmission/opensubtitles.conf"
TOKEN_FILE="/tmp/opensubtitles-token"
TOKEN_EXPIRY_FILE="/tmp/opensubtitles-token-expiry"
API_BASE="https://api.opensubtitles.com/api/v1"
OSHASH="/etc/transmission/oshash.lua"
VIDEO_EXTENSIONS="mkv mp4 avi m4v"

log() { logger -t "$TAG" "$*"; }

# ── Load config ──────────────────────────────────────────────────────
if [ ! -f "$CONF" ]; then
    log "Config not found: $CONF — exiting"
    exit 0
fi
. "$CONF"

if [ "$OS_DOWNLOAD_SUBS" = "no" ]; then
    log "Subtitle downloading disabled (OS_DOWNLOAD_SUBS=no)"
    exit 0
fi

if [ -z "$OS_API_KEY" ] || [ "$OS_API_KEY" = "your_api_key_here" ]; then
    log "API key not configured — exiting"
    exit 0
fi

# ── Torrent path ─────────────────────────────────────────────────────
TORRENT_PATH="${TR_TORRENT_DIR}/${TR_TORRENT_NAME}"
if [ ! -e "$TORRENT_PATH" ]; then
    log "Torrent path not found: $TORRENT_PATH"
    exit 0
fi

# ── Helper: check for embedded English subtitles ─────────────────────
has_english_subs() {
    command -v ffprobe >/dev/null 2>&1 || return 1
    ffprobe -loglevel error -select_streams s \
      -show_entries stream_tags=language \
      -of csv=p=0 "$1" 2>/dev/null | grep -qi 'eng'
}

# ── Helper: get/refresh JWT token ────────────────────────────────────
get_token() {
    # Check cached token
    if [ -f "$TOKEN_FILE" ] && [ -f "$TOKEN_EXPIRY_FILE" ]; then
        expiry=$(cat "$TOKEN_EXPIRY_FILE")
        now=$(date +%s)
        if [ "$now" -lt "$expiry" ] 2>/dev/null; then
            cat "$TOKEN_FILE"
            return 0
        fi
    fi

    # Login for new token
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/login" \
        -H "Api-Key: $OS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$OS_USER\",\"password\":\"$OS_PASS\"}")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log "Login failed (HTTP $http_code)"
        return 1
    fi

    token=$(echo "$body" | jsonfilter -e '@.token' 2>/dev/null)
    if [ -z "$token" ]; then
        log "Login response missing token"
        return 1
    fi

    echo "$token" > "$TOKEN_FILE"
    # Expire in 23 hours (tokens last 24h, refresh early)
    echo $(( $(date +%s) + 82800 )) > "$TOKEN_EXPIRY_FILE"
    echo "$token"
}

# ── Helper: API request with auth retry ──────────────────────────────
api_get() {
    url="$1"
    token=$(get_token) || return 1

    response=$(curl -s -w "\n%{http_code}" -X GET "$url" \
        -H "Api-Key: $OS_API_KEY" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    # Retry on 401 (expired token)
    if [ "$http_code" = "401" ]; then
        rm -f "$TOKEN_FILE" "$TOKEN_EXPIRY_FILE"
        token=$(get_token) || return 1
        response=$(curl -s -w "\n%{http_code}" -X GET "$url" \
            -H "Api-Key: $OS_API_KEY" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | sed '$d')
    fi

    if [ "$http_code" != "200" ]; then
        log "API GET failed (HTTP $http_code): $url"
        return 1
    fi

    echo "$body"
}

api_post() {
    url="$1"
    data="$2"
    token=$(get_token) || return 1

    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
        -H "Api-Key: $OS_API_KEY" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$data")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "401" ]; then
        rm -f "$TOKEN_FILE" "$TOKEN_EXPIRY_FILE"
        token=$(get_token) || return 1
        response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
            -H "Api-Key: $OS_API_KEY" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$data")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | sed '$d')
    fi

    if [ "$http_code" != "200" ]; then
        log "API POST failed (HTTP $http_code): $url"
        return 1
    fi

    echo "$body"
}

# ── Helper: download subtitle for a single video file ────────────────
process_video() {
    video_file="$1"
    basename_noext="${video_file%.*}"
    srt_file="${basename_noext}.${OS_LANG:-en}.srt"

    # Skip if .srt already exists
    if [ -f "$srt_file" ]; then
        log "Subtitle already exists: $srt_file"
        return 0
    fi

    # Check embedded subtitles (if enabled and ffprobe available)
    if [ "$OS_DETECT_EMBEDDED" != "no" ]; then
        if has_english_subs "$video_file"; then
            log "Embedded English subtitles found, skipping: $video_file"
            return 0
        fi
    fi

    # Compute OpenSubtitles hash
    hash=""
    if [ -f "$OSHASH" ] && command -v lua >/dev/null 2>&1; then
        hash=$(lua "$OSHASH" "$video_file" 2>/dev/null)
    fi

    filename=$(basename "$video_file")
    file_id=""

    # Search by hash first
    if [ -n "$hash" ]; then
        log "Searching by hash ($hash): $filename"
        result=$(api_get "$API_BASE/subtitles?moviehash=$hash&languages=${OS_LANG:-en}") || true
        if [ -n "$result" ]; then
            file_id=$(echo "$result" | jsonfilter -e '@.data[0].attributes.files[0].file_id' 2>/dev/null)
        fi
    fi

    # Fallback: search by filename
    if [ -z "$file_id" ]; then
        query=$(echo "$filename" | sed 's/\.[^.]*$//')
        log "Searching by name ($query): $filename"
        result=$(api_get "$API_BASE/subtitles?query=$query&languages=${OS_LANG:-en}") || true
        if [ -n "$result" ]; then
            file_id=$(echo "$result" | jsonfilter -e '@.data[0].attributes.files[0].file_id' 2>/dev/null)
        fi
    fi

    if [ -z "$file_id" ]; then
        log "No subtitles found for: $filename"
        return 0
    fi

    # Download subtitle
    log "Downloading subtitle (file_id=$file_id) for: $filename"
    dl_response=$(api_post "$API_BASE/download" "{\"file_id\":$file_id}") || {
        log "Download request failed for: $filename"
        return 0
    }

    dl_link=$(echo "$dl_response" | jsonfilter -e '@.link' 2>/dev/null)
    remaining=$(echo "$dl_response" | jsonfilter -e '@.remaining' 2>/dev/null)

    if [ -z "$dl_link" ]; then
        log "No download link in response for: $filename"
        return 0
    fi

    if curl -s -o "$srt_file" "$dl_link"; then
        log "Saved subtitle: $srt_file (quota remaining: ${remaining:-unknown})"
    else
        log "Failed to download subtitle file for: $filename"
        rm -f "$srt_file"
    fi
}

# ── Main: find and process video files ───────────────────────────────
log "Processing torrent: $TR_TORRENT_NAME"

find_videos() {
    if [ -f "$TORRENT_PATH" ]; then
        # Single file torrent
        for ext in $VIDEO_EXTENSIONS; do
            case "$TORRENT_PATH" in
                *."$ext") echo "$TORRENT_PATH"; return ;;
            esac
        done
    elif [ -d "$TORRENT_PATH" ]; then
        # Directory torrent — find all video files
        for ext in $VIDEO_EXTENSIONS; do
            find "$TORRENT_PATH" -type f -name "*.$ext"
        done
    fi
}

count=0
find_videos | while IFS= read -r video; do
    [ -n "$video" ] || continue
    process_video "$video"
    count=$((count + 1))
done

log "Done processing torrent: $TR_TORRENT_NAME"
