# ORB Virtualization Makefile

.PHONY: up down restart logs status help

# Default target
help:
	@echo "🎮 ORB Virtualization Manager"
	@echo "--------------------------------"
	@echo "Make commands:"
	@echo "  make up      - Start the Windows environment (checks Docker & permissions)"
	@echo "  make down    - Stop the environment (Safely saves state)"
	@echo "  make restart - Restart the environment"
	@echo "  make logs    - View and follow container logs"
	@echo "  make status  - Check container status"

up:
	@./start-orb.sh

down:
	@echo "🛑 Stopping ORB..."
	@docker compose down
	@echo "✅ ORB stopped. Data is safely stored in ./storage"

restart: down up

# 🏗️ Build Golden Image (Takes time!)
build-image:
	@echo "🔨 Building Golden Image (alkami/windows-golden)..."
	@echo "⚠️  This copies the 64GB+ disk. verified disk exists?"
	@ls -lh storage/data.img
	docker build -f Dockerfile.golden -t alkami/windows-golden .
	@echo "✅ Build Complete! You can now push 'alkami/windows-golden' to Docker Hub."

logs:
	@docker compose logs -f

status:
	@docker compose ps
