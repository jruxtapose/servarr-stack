# Servarr VPN Stack

A secure, fully contained media server stack running on Docker. All traffic is routed through a VPN tunnel (Gluetun) to ensure privacy.

**Services Included:**
* **Jellyfin:** Media Server
* **Sonarr:** TV Show Management
* **Radarr:** Movie Management
* **Prowlarr:** Indexer Manager
* **qBittorrent:** Downloader (VPN Tunneled)
* **Flaresolverr:** Cloudflare Solver
* **Gluetun:** VPN Client (OpenVPN & WireGuard support)

---

## ⚠️ Requirements

1.  **Linux OS** (Ubuntu, Debian, Fedora, etc.)
2.  **Docker & Docker Compose** installed and running.
3.  **VPN Subscription** (Supports AirVPN, Mullvad, NordVPN, PIA, ProtonVPN, and many others).

---

## 🚀 Installation

### 1. Clone the Repository
**CRITICAL:** To ensure permission consistency, this repository **MUST** be cloned to your home directory exactly as shown below:

```bash
cd ~
git clone [https://github.com/your-username/servarr-stack.git](https://github.com/your-username/servarr-stack.git)
cd servarr-stack
```

### 2. Run the Configurator
We provide a helper script (`setup.sh`) to generate your environment variables and fix folder permissions.

```bash
chmod +x setup.sh
./setup.sh
```

**What this script does:**
* Detects your local subnet (so you can access the WebUIs).
* Asks for your VPN credentials (supports WireGuard & OpenVPN).
* Generates a secure `.env` file.
* **Fixes permissions** on the `.config` and `data` folders to prevent "Access Denied" errors.

### 3. Verify & Start
The script will output the contents of the generated `.env` file. Review it to ensure your settings are correct.

If everything looks good, start the stack:

```bash
docker compose up -d
```

---

## 🌐 Accessing Services

Once the stack is running, you can access the services via your web browser using your server's LAN IP address.

| Service | Port | URL |
| :--- | :--- | :--- |
| **Jellyfin** | 8096 | `http://<SERVER-IP>:8096` |
| **Sonarr** | 8989 | `http://<SERVER-IP>:8989` |
| **Radarr** | 7878 | `http://<SERVER-IP>:7878` |
| **Prowlarr** | 9696 | `http://<SERVER-IP>:9696` |
| **qBittorrent** | 8091 | `http://<SERVER-IP>:8091` |

*Note: The initial username/password for qBittorrent can be found by running 
    ```bash
    docker logs qbittorrent 
    ```
    after running 
    ```bash
    docker compose up -d
    ```
    *

---

## 📂 Folder Structure

This stack uses a **self-contained** directory structure. Everything lives inside the `~/servarr-stack` folder.

```text
/home/user/servarr-stack/
├── .env                  # Generated Configuration (API Keys, VPN creds)
├── docker-compose.yml    # Stack Definition
├── setup.sh              # Configurator Script
├── .config/              # Application Configs (Databases, Settings)
│   ├── jellyfin/
│   ├── sonarr/
│   └── ...
└── data/                 # Your Media Library
    ├── torrents/         # Active Downloads
    └── media/
        ├── movies/       # Radarr Library
        └── tv/           # Sonarr Library
```

---

## 🔧 Maintenance

### Updating Containers
To update all services to the latest version:

```bash
docker compose pull
docker compose up -d
```

### Changing VPN Settings
If you need to change your VPN provider or credentials:
1.  Run `./setup.sh` again to regenerate the `.env` file.
2.  Restart the stack: `docker compose up -d --force-recreate`

---

## 🛑 Uninstall

To completely remove the stack and all data:

1.  Stop the containers:
    ```bash
    docker compose down
    ```
2.  Delete the repository folder:
    ```bash
    rm -rf ~/servarr-stack
    ```
    *Warning: This will permanently delete your database configurations and your media library.*