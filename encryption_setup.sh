#!/bin/bash
set -e

echo "=== Gocryptfs Encryption Setup ==="
HOMELAB_ROOT="${HOMELAB_ROOT:-$HOME/homelab}"
NEXTCLOUD_DATA_DIR="$HOMELAB_ROOT/data/nextcloud"
ENCRYPTED_DIR="$HOMELAB_ROOT/encrypted"

echo "We will mount $NEXTCLOUD_DATA_DIR onto an encrypted directory."
echo "The encrypted files will physically rest in $ENCRYPTED_DIR."
echo "Note: Execute this script on your Raspberry Pi, not your host Mac."

if ! command -v gocryptfs &> /dev/null; then
  echo "gocryptfs not installed. Please run setup_homelab.sh first."
  exit 1
fi

if mount | grep -q "$NEXTCLOUD_DATA_DIR"; then
    echo "Directory is already mounted."
    exit 0
fi

if [ ! -f "$ENCRYPTED_DIR/gocryptfs.conf" ]; then
    echo "Initializing new encrypted vault in $ENCRYPTED_DIR..."
    gocryptfs -init "$ENCRYPTED_DIR"
fi

echo "Mounting the encrypted vault..."
gocryptfs "$ENCRYPTED_DIR" "$NEXTCLOUD_DATA_DIR"

echo "Mounted successfully. Data written to $NEXTCLOUD_DATA_DIR is now transparently encrypted."
