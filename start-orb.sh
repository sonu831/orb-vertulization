#!/bin/bash
echo "🚀 Starting ORB Virtualization Project..."

# Check if Docker is running (with timeout)
if ! timeout 5s docker info > /dev/null 2>&1; then
  echo "❌ Error: Docker is not running or unresponsive. Please start/restart Docker Desktop."
  exit 1
fi

# Switch to Docker Desktop context if available (with timeout)
if timeout 5s docker context use desktop-linux > /dev/null 2>&1; then
  echo "✅ Switched to Docker Desktop context (desktop-linux)"
fi

# Start the container
docker compose up -d

echo "--------------------------------------------------"
echo "✅ Windows 11 is booting up!"
echo "📍 Browser UI: http://localhost:8006"
echo "📍 RDP Access: localhost (User: docker / Pass: [none])"
echo "--------------------------------------------------"
echo "Note: The first run will take 15-20 mins to download Windows."
echo "Use 'docker compose logs -f' to watch the download progress."
echo "--------------------------------------------------"
docker compose logs -f
