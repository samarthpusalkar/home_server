#!/bin/bash

# Management script to ensure Docker containers don't interfere with Astrophotography

if [ "$1" == "start" ]; then
    echo "Starting Astrophotography Session..."
    echo "Pausing non-essential containers..."
    docker pause minecraft openwebui ollama nextcloud cloudflared playit 2>/dev/null || echo "Some containers were not running."
    
    # Optionally lower Docker daemon priority to keep host CPU clear
    # pgrep dockerd gets the docker daemon PID
    DOCKER_PID=$(pgrep dockerd || true)
    if [ ! -z "$DOCKER_PID" ]; then
        sudo renice -n 10 -p $DOCKER_PID 2>/dev/null || true
        echo "Docker daemon deprioritized."
    fi
    echo "Session mode active. Clear skies!"

elif [ "$1" == "stop" ]; then
    echo "Ending Astrophotography Session..."
    echo "Unpausing containers..."
    docker unpause minecraft openwebui ollama nextcloud cloudflared playit 2>/dev/null || echo "Some containers were not paused."
    
    # Restore normal priority
    DOCKER_PID=$(pgrep dockerd || true)
    if [ ! -z "$DOCKER_PID" ]; then
        sudo renice -n 0 -p $DOCKER_PID 2>/dev/null || true
        echo "Docker daemon restored to normal priority."
    fi
    echo "Services restored."
else
    echo "Usage: ./astro_session.sh [start|stop]"
    echo "  start : Pause homelab containers for an astronomy session."
    echo "  stop  : Resume homelab containers."
fi
