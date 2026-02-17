# ORB Virtualization Makefile

.PHONY: up down restart logs status help convert-qcow2 upload-s3 package-client

# Default target
help:
	@echo "ORB Virtualization Manager"
	@echo "--------------------------------"
	@echo "Runtime:"
	@echo "  make up              - Start the Windows environment"
	@echo "  make down            - Stop (saves state)"
	@echo "  make restart         - Restart"
	@echo "  make logs            - Follow container logs"
	@echo "  make status          - Show container status"
	@echo ""
	@echo "Distribution (dev machine):"
	@echo "  make convert-qcow2   - Convert data.img -> data.qcow2 (~70% smaller)"
	@echo "  make upload-s3       - Upload data.qcow2 to S3  (set S3_BUCKET=your-bucket)"
	@echo "  make package-client  - Create client install package (client.zip)"
	@echo ""
	@echo "Legacy:"
	@echo "  make build-image     - Build full golden Docker image (needs 150GB space)"
up:
	@bash ./start-orb.sh

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

# ----------------------------------------------------------------------------
# Distribution targets
# ----------------------------------------------------------------------------

# Convert data.img → data.qcow2 (compressed, ~70% smaller)
# Output defaults to storage/data.qcow2
# To output to another drive: make convert-qcow2 OUTPUT=/mnt/external/data.qcow2
OUTPUT ?= $(CURDIR)/storage/data.qcow2

convert-qcow2:
	@echo "Converting data.img -> qcow2 (takes 20-60 min)..."
	@bash ./scripts/convert-to-qcow2.sh --output $(OUTPUT)

# Upload data.qcow2 to S3
# Usage: make upload-s3 S3_BUCKET=my-orb-images
S3_BUCKET ?= orb-golden-images
QCOW2_FILE ?= $(CURDIR)/storage/data.qcow2

upload-s3:
	@if [ ! -f "$(QCOW2_FILE)" ]; then \
		echo "ERROR: $(QCOW2_FILE) not found. Run 'make convert-qcow2' first."; \
		exit 1; \
	fi
	@echo "Uploading $(QCOW2_FILE) to s3://$(S3_BUCKET)/orb/v1/data.qcow2 ..."
	aws s3 cp "$(QCOW2_FILE)" "s3://$(S3_BUCKET)/orb/v1/data.qcow2" \
		--storage-class STANDARD_IA \
		--no-progress
	@echo ""
	@echo "Upload done. Generate a client URL with:"
	@echo "  aws s3 presign s3://$(S3_BUCKET)/orb/v1/data.qcow2 --expires-in 604800"

# One-step convert + upload
convert-and-upload: convert-qcow2
	@$(MAKE) upload-s3 S3_BUCKET=$(S3_BUCKET)

# Package client install bundle (zip with install.sh + docker-compose.yml)
# Usage: DATA_IMG_URL=https://... make package-client
DATA_IMG_URL ?=

package-client:
	@if [ -z "$(DATA_IMG_URL)" ]; then \
		echo "ERROR: Set DATA_IMG_URL first."; \
		echo "  make package-client DATA_IMG_URL=https://s3.amazonaws.com/..."; \
		exit 1; \
	fi
	@echo "Packaging client bundle..."
	@mkdir -p /tmp/orb-client
	@cp scripts/install.sh /tmp/orb-client/install.sh
	@chmod +x /tmp/orb-client/install.sh
	@echo "DATA_IMG_URL=$(DATA_IMG_URL)" > /tmp/orb-client/.env
	@cp docker-compose.yml /tmp/orb-client/docker-compose.yml
	@cd /tmp && zip -r orb-client.zip orb-client/
	@cp /tmp/orb-client.zip ./orb-client.zip
	@rm -rf /tmp/orb-client /tmp/orb-client.zip
	@echo ""
	@echo "Created: orb-client.zip"
	@echo "Send this zip to the client. They run:"
	@echo "  unzip orb-client.zip && cd orb-client && chmod +x install.sh && ./install.sh"
