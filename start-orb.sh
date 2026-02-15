#!/bin/bash
echo "🚀 Starting ORB Virtualization Project..."

# Check if Docker is running (with timeout)
if ! timeout 5s docker info > /dev/null 2>&1; then
  # Check if it's a permission issue with the socket
  if [ -S /var/run/docker.sock ] && [ ! -w /var/run/docker.sock ]; then
      echo "❌ Error: Permission denied accessing Docker socket."
      echo "   You need to add your user to the 'docker' group:"
      echo "   Run: sudo usermod -aG docker \$USER && newgrp docker"
      exit 1
  fi
  echo "❌ Error: Docker is not running or unresponsive."
  exit 1
fi

# Prefer 'default' context for KVM support (Native Docker)
if docker context use default > /dev/null 2>&1; then
    echo "✅ Switched to Native Docker context (default) for KVM support."
    
    # Check if user has KVM permissions
    if [ ! -r /dev/kvm ]; then
        echo "⚠️  WARNING: You do not have permission to access /dev/kvm."
        echo "   Run: sudo usermod -aG kvm \$USER && newgrp docker"
    fi
elif timeout 5s docker context use desktop-linux > /dev/null 2>&1; then
  echo "⚠️  Switched to Docker Desktop context (desktop-linux). KVM MIGHT NOT WORK."
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
