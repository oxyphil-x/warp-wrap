# WARP-over-Amnezia Gateway

### Tunnel Purpose and Concept
The primary goal of this project is to create a **Nested VPN Gateway**. While AmneziaWG provides an obfuscated entry point to bypass restrictive firewalls, routing that traffic through Cloudflare WARP adds an additional layer of anonymity and allows the server to act as a transparent proxy for all connected clients.

* **Entry Point**: Clients connect via AmneziaWG (Interface: `amn0`).
* **Exit Point**: All client traffic is "wrapped" and sent out via Cloudflare WARP (Interface: `wgcf-profile`).
* **Use Case**: Bypassing censorship while maintaining high-speed routing through Cloudflare’s global network.

### Routing Scheme
This setup uses **Policy-Based Routing (PBR)** to ensure that the server remains manageable (SSH stays open) while client traffic is force-routed through the tunnel.

| Priority | Action | Purpose |
| :--- | :--- | :--- |
| **90** | `lookup main` | **Loop Breaker**: Forces Amnezia's encrypted UDP traffic to use the physical internet, preventing a routing loop. |
| **100** | `lookup 51820` | **The Wrap**: Forces all decrypted traffic from the `amn0` subnet into the WARP interface. |
| **Default** | `lookup main` | **SSH Safety**: Ensures standard server traffic (like your SSH session) ignores the VPN and stays on the main internet. |

### The Deployment Script
The `deploy-warp.sh` file is an all-in-one automation tool designed for fresh Debian/Ubuntu systems.

**What it does:**
1.  **Dependency Management**: Installs `wireguard-tools`, `jq`, `resolvconf`, and `docker` utilities.
2.  **Binary Acquisition**: Dynamically fetches the latest version of `wgcf` from GitHub.
3.  **WARP Registration**: Automatically registers a new Cloudflare account and generates the `.conf` profile.
4.  **Auto-Hardening**: Patches the config with `Table = off` to prevent system-wide lockouts and adds `PersistentKeepalive` for stability.
5.  **Smart Detection**: On every start, the script "sniffs" the environment to detect the `amn0` subnet and the specific Docker/System port Amnezia is listening on.

**How to run it:**
```bash
chmod +x deploy-warp.sh
sudo ./deploy-warp.sh
```

### Service Management
The installation creates a systemd service to manage the tunnel lifecycle and a watchdog to ensure 99.9% uptime.

**Start the tunnel:**
```bash
sudo systemctl start warp-tunnel
```

**Enable on boot:**
```bash
sudo systemctl enable warp-tunnel
```

**Stop and Cleanup:**
The service is configured with a custom `ExecStop` that triggers a full cleanup, removing all IPTables rules and routing policies to return the server to its original state.
```bash
sudo systemctl stop warp-tunnel
```

**Health Check:**
A watchdog script runs every **1 minute** via crontab. It pings `1.1.1.1` through the `wgcf-profile` interface; if the ping fails, it automatically restarts the service.