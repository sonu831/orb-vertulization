#!/bin/bash
set -e

echo "🏗️  Setting up ORB Virtualization Project..."

# Create Directories
mkdir -p orb-virtualization/storage
cd orb-virtualization

# --- Create docker-compose.yml ---
cat << 'DOCKER' > docker-compose.yml
services:
  windows:
    image: dockurr/windows
    container_name: orb-win11
    environment:
      VERSION: "11"
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "64G"
      KVM: "N"
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    volumes:
      - ./storage:/storage
    stop_grace_period: 2m
    restart: on-failure
DOCKER

# --- Create README.md ---
cat << 'README' > README.md
# 🌐 ORB Virtualization (Orbless Initiative)

## Overview
This project runs a full Windows 11 environment inside Docker to bypass GCC admin restrictions.

## Quick Start
1. Run: \`./start-orb.sh\`
2. Open Browser: http://localhost:8006
3. RDP Address: localhost (User: docker, No Password)

## Data
All files saved in \`C:\\storage\` inside Windows are backed up to your Mac's \`./storage\` folder.
README

# --- Create start-orb.sh ---
cat << 'START' > start-orb.sh
#!/bin/bash
echo "🚀 Initializing ORB Environment..."

# 1. Check Docker
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running! Please open Docker Desktop."
  exit 1
fi

# 2. Fix Permissions (Mac Specific)
xattr -d com.apple.quarantine start-orb.sh 2>/dev/null || true

# 3. Start
docker compose up -d

echo "✅ Success! Windows is booting."
echo "-------------------------------------"
echo "🌐 Browser: http://localhost:8006"
echo "💻 RDP:     localhost:3389"
echo "-------------------------------------"
echo "Monitor download: docker compose logs -f"
START

chmod +x start-orb.sh

echo "✅ Project created in folder 'orb-virtualization'!"
echo "👉 To start, run: cd orb-virtualization && ./start-orb.sh"
