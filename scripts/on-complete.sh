#!/bin/sh
# /etc/transmission/on-complete.sh — Copy completed torrent to Movies folder for DLNA
# Called by Transmission's script-torrent-done mechanism.
#
# Env vars set by Transmission:
#   TR_TORRENT_DIR  — directory containing the torrent
#   TR_TORRENT_NAME — name of the torrent (file or directory)
#   TR_TORRENT_ID   — numeric torrent ID

MOVIES="/tmp/mountd/disk1_part1/Movies"
TAG="transmission-complete"
SRC="$TR_TORRENT_DIR/$TR_TORRENT_NAME"

logger -t "$TAG" "Torrent complete: $TR_TORRENT_NAME"

if [ -d "$SRC" ]; then
    # Directory (multi-file torrent) — copy entire folder
    cp -a "$SRC" "$MOVIES/"
    logger -t "$TAG" "Copied folder to $MOVIES/$TR_TORRENT_NAME"
elif [ -f "$SRC" ]; then
    # Single file — copy to Movies root
    cp -a "$SRC" "$MOVIES/"
    logger -t "$TAG" "Copied file to $MOVIES/$TR_TORRENT_NAME"
else
    logger -t "$TAG" "ERROR: source not found: $SRC"
fi
