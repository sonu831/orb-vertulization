# 🌐 ORB Virtualization: The Orbless Initiative

> **Vision:** A scalable, containerized Windows 11 environment that eliminates hardware dependencies and drastically reduces onboarding time.

## 🚀 Overview

The **Orbless Initiative** aims to solve the critical "20-day onboarding" problem by providing a pre-configured, portable Windows 11 environment that runs inside Docker.

This project creates a "Golden Image" for development, containing all necessary prerequisites (including the **Merlin SDK** and platform tools) pre-installed. This image can be flashed onto any system—whether it's a MacBook (M1/M2/M3), a Linux server, or a cloud instance—instantly providing a fully functional development environment.

## 🎯 Key Objectives

1.  **Zero-Touch Onboarding:** Reduce setup time from weeks to minutes.
2.  **Cross-Platform Compatibility:** Run a full Windows dev environment on macOS (Apple Silicon), Linux, and Windows hosts.
3.  **Scalability:** Create a "write once, run anywhere" Docker image that can be deployed across the organization.
4.  **Infrastructure as Code:** Entire environment defined in `docker-compose.yml` for reproducibility.

## 🛠️ Features

-   **Windows 11 Pro:** Automatically downloads and installs the latest version.
-   **Pre-Configured Environment:** Ready for **Merlin** and other Alkami SDK tools.
-   **Hardware Agnostic:**
    -   **Intel/AMD:** Utilizes KVM acceleration for near-native performance.
    -   **Apple Silicon (M1/M2/M3):** configured to run via software emulation (QEMU) where KVM is unavailable.
-   **Persistent Storage:** All data in `C:\storage` is mirrored to your local machine (`./storage` folder), ensuring data safety even if the container is destroyed.
-   **Dual Access Modes:**
    -   **Web Interface:** Access smoothly via browser at `http://localhost:8006`.
    -   **RDP:** Connect using Microsoft Remote Desktop at `localhost:3389`.

## 📦 Project Structure

```bash
orb-virtualization/
├── docker-compose.yml  # Container definition (CPU, RAM, Ports)
├── setup_project.sh    # One-click setup script (Generates project files)
├── start-orb.sh        # Smart startup launcher (Fixes permissions & Docker checks)
├── storage/            # Shared volume (Host <-> Guest)
└── README.md           # This documentation
```

## 🚀 Getting Started

### Prerequisites

-   **Docker Desktop** (installed and running).
-   **40GB+ Free Disk Space** (Windows is large!).
-   **8GB+ RAM** allocated to Docker (configured in `docker-compose.yml`).

### Identification & Setup

1.  **Clone/Download** this repository.
2.  **Initialize the Project:**
    ```bash
    ./setup_project.sh
    ```
    *This creates the necessary directories and configuration files.*

3.  **Launch the Environment:**
    ```bash
    ./start-orb.sh
    ```
    *This script handles Mac security permissions (quarantine) and starts the container.*

### ⏳ Installation Process

*   **First Run:** The container will download the Windows 11 ISO (~5-6GB) and perform the installation automation.
*   **Time Estimate:** 15–30 minutes depending on internet speed.
*   **Monitor Progress:**
    ```bash
    docker compose logs -f
    ```

## 🖥️ Accessing Your Environment

Once the installation is complete:

1.  **Web Browser (Quick Access):**
    Open [http://localhost:8006](http://localhost:8006) to interact with the Windows desktop directly in your browser.

2.  **Remote Desktop (Performance):**
    Use **Microsoft Remote Desktop** app.
    -   **PC Name:** `localhost`
    -   **User:** `docker`
    -   **Password:** *(Leave empty)*

## ⚙️ Configuration (docker-compose.yml)

You can adjust these settings in `setup_project.sh` or directly in `docker-compose.yml`:

| Setting     | Default | Description                                  |
| :---------- | :------ | :------------------------------------------- |
| `RAM_SIZE`  | `8G`    | Allocate more RAM for heavier workloads.     |
| `CPU_CORES` | `4`     | More cores = smoother UI.                    |
| `DISK_SIZE` | `64G`   | Virtual C: drive size.                       |
| `KvM`       | `N`     | Set to `Y` for Linux hosts, `N` for Mac M1/M2. |

> **Note for Mac M1/M2 Users:** KVM acceleration is inherently unavailable for x86 Windows emulation on ARM chips. The environment is configured with `KVM: "N"` to ensure stability, though performance will be slower than native virtualization.

## 🔮 Future Roadmap (Scalability)

-   [ ] **Golden Image Creation:** Snapshot the fully configured container (with Merlin installed) to a Docker registry.
-   [ ] **Instant Provisioning:** Developers `docker pull` the pre-baked image instead of installing from ISO.
-   [ ] **Cloud Integration:** Deploy the same container to AWS/Azure for remote development scenarios.

---
*Maintained by the DevOps Architecture Team - Alkami India GCC*
