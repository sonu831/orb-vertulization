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

## 💾 Data Persistence (YES, it saves!)

**Q: "If I stop Docker, do I lose my work?"**
**A: NO.**

All your data is saved in the `./storage` folder in your project directory.
*   The `C:\` drive inside Windows is just for the OS.
*   **Best Practice:** Always save your large files and code in the `storage` folder on Mac.
*   **Persistence:** The Windows installation (`data.img`) lives here. This ensures you **NEVER** face a fresh install on restart.
*   **Ease of Use:** This same folder appears inside Windows as a Network Drive (`\\host.lan\Data`).

## 📦 Project Structure

```bash
orb-virtualization/
├── docker-compose.yml  # Container definition (CPU, RAM, Ports)
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
2.  **Launch the Environment:**
    ```bash
    make up
    ```
    *(Or run `./start-orb.sh` directly)*

### ⏳ Installation Process

*   **First Run:** The container will download the Windows 11 ISO (~5-6GB) and perform the installation automation.
*   **Time Estimate:** 15–30 minutes depending on internet speed.
*   **Monitor Progress:**
    ```bash
*   **Monitor Progress:**
    ```bash
    make logs
    ```

    > **📝 Note:** During the first run, you might see the process "stuck" at the Windows logo or a blue screen for 10-20 minutes. **This is normal.** It is installing Windows in the background. Check the terminal logs to see the actual progress.

## 🖥️ Accessing Your Environment

Once the installation is complete, you have **two ways** to connect:

### Method 1: Web Browser (Quick Access)
This is the easiest way. It runs entirely inside Chrome/Safari.

1.  **Open URL:** [http://127.0.0.1:8006](http://127.0.0.1:8006)
2.  **View:** You will see the Windows screen directly.

    > **Note:** This IS the web-based viewer you mentioned. It provides basic mouse/keyboard control.

### Method 2: Microsoft Remote Desktop (High Performance)
For a smoother experience (better resolution, clipboard sync), use the native app.

1.  **Download:** [Microsoft Remote Desktop](https://apps.apple.com/us/app/microsoft-remote-desktop/id1295203466) from the Mac App Store.
2.  **Add PC:**
    *   **PC Name:** `localhost:3389`
    *   **User Account:** `alkami` (Add a user with this name)
    *   **Password:** `alkami123`
    *   **Note:** The system is pre-configured with these credentials.
3.  **Connect:** Double-click the new PC entry.



## 📂 How to Transfer Files (e.g., Merlin)

### Method 1: Shared Folder (Best for large files)
1.  **On Mac:** Copy file to `orb-virtualization/storage`.
2.  **Inside Windows:**
    *   Open **File Explorer**.
    *   In the address bar path, type `\\host.lan` and hit Enter.
    *   Open the `Data` folder. **This is your storage.**
    *   *Troubleshooting:* If `host.lan` doesn't work, try `\\192.168.65.2`.

### Method 2: RDP Drag-and-Drop (Easiest)
**Requirement:** You MUST be using the **Microsoft Remote Desktop** app (Method 2 above), NOT the browser.
1.  Just drag a file from Mac and drop it in the RDP window.
2.  *Troubleshooting:* If it fails, check the RDP App settings > Edit PC > **Devices & Audio** > Ensure "Clipboard" is checked.

## ⚙️ Configuration (docker-compose.yml)

You can adjust these settings in `docker-compose.yml`:

| Setting     | Default | Description                                  |
| :---------- | :------ | :------------------------------------------- |
| `RAM_SIZE`  | `24G`   | Allocate more RAM for heavier workloads.     |
| `CPU_CORES` | `14`    | More cores = smoother UI.                    |
| `DISK_SIZE` | `64G`   | Virtual C: drive size.                       |
| `KvM`       | `N`     | Set to `Y` for Linux hosts, `N` for Mac M1/M2. |

## ⚠️ CRITICAL PERFORMANCE NOTICE: KVM & Emulation

This project supports two modes of operation. Please understand the difference:

| Mode | Platform | Speed | Description |
| :--- | :--- | :--- | :--- |
| **Native (KVM)** | **Linux / AWS** | 🚀 **100%** | Uses Hardware Virtualization. Fast and fluid. |
| **Emulation (QEMU)** | **Mac M1/M2/M3** | 🐢 **~10%** | Uses Software Emulation. Functional, but slower. |

### 🚨 The "10x Slower" Warning
If you see this log on your Mac:
> `Warning: KVM acceleration is disabled, this will cause the machine to run about 10 times slower!`

**DO NOT PANIC.** This is expected behavior on Apple Silicon.
*   **Problem:** Mac chips (ARM) cannot natively virtualize Windows (x86) instructions.
*   **Workaround:** We force-enable "Emulation Mode" and give it massive resources (14 Cores / 24GB RAM) to make it usable.

### ✅ The Solution: Use Linux or AWS
If the emulation speed is too slow for your workflow, **you MUST move to a Linux-based environment.**
Running this container on a standard **Linux machine** (or AWS EC2) unlocks KVM, giving you **10x performance** instantly.

See the **[Production Deployment (AWS)]** section below for the high-speed setup.
> *   **Do NOT worry:** This is **normal**. We compensated by giving it massive resources (14 Cores / 24GB RAM), so it will still be usable. Just ignore the warning.
>
> **💡 Pro Tip for Speed:** If you need native-speed virtualization (KVM), consider running this Docker container on a **Linux machine**. On Linux, KVM is fully supported and performance will be roughly 10x faster than on Mac emulation.

## ☁️ Production Deployment (AWS) - The Golden Image

To run your "Golden Image" for the team, use a minimal, high-performance AWS setup. We don't need to install Windows; we just run the baked Docker container.

### Recommended Configuration
| Component | Recommendation | Reason |
| :--- | :--- | :--- |
| **Instance Type** | **`c5.4xlarge`** or **`m5.4xlarge`** | 16 vCPUs / 32-64GB RAM. Native KVM speed. |
| **OS (AMI)** | **Amazon Linux 2023** or **Ubuntu Server 24.04** | **Minimal OS.** No GUI needed. Just Docker + KVM. |
| **Disk** | **gp3 (100GB+)** | Fast storage for the Docker image layers. |

### 🚀 Instant Launch (User Data Script)
Paste this into the **User Data** field when launching the EC2 instance. It will auto-install Docker and start your environment.

```bash
#!/bin/bash
# 1. Update & Install Docker + KVM
yum update -y
yum install -y docker qemu-kvm libvirt
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# 2. Pull & Run the Golden Image (Instant Start)
# Replace 'v1' with your actual tag
docker run -d \
  --name windows-orb \
  --device /dev/kvm \
  --cap-add NET_ADMIN \
  -p 8006:8006 -p 3389:3389 \
  -v /home/ec2-user/storage:/storage \
  alkami/windows-golden:latest
```
*(The Windows environment will be live at `http://<EC2-IP>:8006` in minutes!)*

## 🛠️ Management Commands (Makefile)

We've included a `Makefile` to make your daily workflow easier:

| Command | Description |
| :--- | :--- |
| `make up` | Starts the container (and fixes Mac permissions). |
| `make down` | Stops the container gracefully. **Data is saved.** |
| `make restart` | Restarts the environment. |
| `make logs` | Shows and follows the logs. |
| `make status` | Checks if the container is running. |

## 🔮 Future Roadmap (Scalability)

-   [ ] **Golden Image Creation:** Snapshot the fully configured container (with Merlin installed) to a Docker registry.
-   [ ] **Instant Provisioning:** Developers `docker pull` the pre-baked image instead of installing from ISO.
-   [ ] **Cloud Integration:** Deploy the same container to AWS/Azure for remote development scenarios.

---
## 📦 Golden Image & Distribution (DevOps)

Once you have installed the **Merlin SDK** and tools, you can "freeze" this environment into a portable Docker image for the rest of the team.

### How to Build the Golden Image
1.  **Stop the Orb:** `make down`
2.  **Run Build:**
    ```bash
    make build-image
    ```
    *(This creates a Docker image `alkami/windows-golden` containing your configured C: drive)*

### How to Distribute
1.  **Push to Registry:**
    ```bash
    docker tag alkami/windows-golden:latest my-registry.alkami.com/orb/windows-11:v1
    docker push my-registry.alkami.com/orb/windows-11:v1
    ```
2.  **Team Usage:**
    Other developers can simply run:
    ```bash
    docker run -it --rm -p 8006:8006 -p 3389:3389 my-registry.alkami.com/orb/windows-11:v1
    ```
    *(No installation required. They start instantly with your tools!)*

---
*Maintained by the DevOps Architecture Team - Alkami India GCC*
