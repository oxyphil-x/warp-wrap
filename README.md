
# WARP-Wrap
**An automated high-performance gateway bridging AmneziaWG obfuscation with Cloudflare WARP routing.**

### 🚀 Concept
This project solves the "Censorship vs. Performance" trade-off. **AmneziaWG** (running on `amn0`) provides an obfuscated entry point to bypass deep-packet inspection (DPI). All traffic entering this gate is then wrapped into **Cloudflare WARP** (`wgcf-profile`) for optimized global routing and privacy.

### 🛣 Routing Scheme
The gateway uses Policy-Based Routing (PBR) to ensure the server remains accessible via SSH while tunneling all client traffic.

* **Priority 90 (Loop Breaker):** Detects the AmneziaWG UDP port and forces it through the physical internet (Table: `main`) to prevent recursive tunnel loops.
* **Priority 100 (The Wrap):** All traffic originating from the `amn0` subnet is force-routed into Table `51820` (the WARP interface).
* **Management:** Standard server traffic (SSH/Updates) stays on the default gateway for zero-lockout reliability.

### 🛠 Installation & Usage
The deployment script is designed for Debian/Ubuntu systems. It dynamically detects your environment (Docker/Bare-metal) and configures everything in one pass.

**Run the installer:**
```bash
curl -fsSL https://raw.githubusercontent.com/kfomichev/warp-wrap/main/deploy-warp.sh -o deploy-warp.sh && chmod +x deploy-warp.sh && sudo ./deploy-warp.sh
```

**What happens during deployment:**
1.  Downloads the latest `wgcf` binary from GitHub.
2.  Registers a new WARP account and patches the config for `Table = off`.
3.  Automatically detects the `amn0` subnet and listening port (via Docker or System Sockets).
4.  Sets up a **1-minute Watchdog** via Crontab.

### ⚙️ Service Management
The tunnel is managed as a standard Systemd service.

* **Start Tunnel:** `sudo systemctl start warp-tunnel`
* **Stop Tunnel:** `sudo systemctl stop warp-tunnel` (Triggers a full routing/IPTables cleanup)
* **Check Logs:** `journalctl -u warp-tunnel -f`
* **Check Tunnel Status:** `wg show`