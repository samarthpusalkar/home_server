#!/bin/bash
set -e

echo "=== Gocryptfs Encryption Setup ==="
echo "We will mount /opt/homelab/data/nextcloud onto an encrypted directory."
echo "The encrypted files will physically rest in /opt/homelab/encrypted."
echo "Note: Execute this script on your Raspberry Pi, not your host Mac."

if ! command -v gocryptfs &> /dev/null; then
  echo "gocryptfs not installed. Please run setup_homelab.sh first."
  exit 1
fi

if mount | grep -q "/opt/homelab/data/nextcloud"; then
    echo "Directory is already mounted."
    exit 0
fi

if [ ! -f /opt/homelab/encrypted/gocryptfs.conf ]; then
    echo "Initializing new encrypted vault in /opt/homelab/encrypted..."
    gocryptfs -init /opt/homelab/encrypted
fi

echo "Mounting the encrypted vault..."
gocryptfs /opt/homelab/encrypted /opt/homelab/data/nextcloud

echo "Mounted successfully. Data written to /opt/homelab/data/nextcloud is now transparently encrypted."
