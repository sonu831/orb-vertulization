#!/bin/bash
echo "🚀 Starting ORB Virtualization Project..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "❌ Error: Docker is not running. Please start Docker Desktop first."
  exit 1
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
