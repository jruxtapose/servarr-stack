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
git clone https://github.com/your-username/servarr-stack.git
cd servarr-stack
```

### 2. Run the Configurator
We provide a helper script (`createenv.sh`) to generate your environment variables and fix folder permissions.

```bash
./createenv.sh
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

You can find this address by runnning 
```
ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++)if($i=="src")print $(i+1)}'
```


| Service | Port | URL |
| :--- | :--- | :--- |
| **Jellyfin** | 8096 | `http://<SERVER-IP>:8096` |
| **Sonarr** | 8989 | `http://<SERVER-IP>:8989` |
| **Radarr** | 7878 | `http://<SERVER-IP>:7878` |
| **Prowlarr** | 9696 | `http://<SERVER-IP>:9696` |
| **qBittorrent** | 8091 | `http://<SERVER-IP>:8091` |

*Note: The initial username/password for qBittorrent can be found by running 
    ```
    docker logs qbittorrent 
    ```
    after spinning up the stack*

---

## 🔗 Post-Installation: Linking the System

Because all containers are routed through the VPN container, they share the same network space. **You must use `localhost` or `127.0.0.1` as the Hostname/IP when connecting apps together.**

### 1. Configure qBittorrent
1.  Open **qBittorrent** (`http://<SERVER-IP>:8091`).
2.  Login with the credentials found in ```docker logs qbittorrent```.
3.  Go to **Tools > Options > Web UI**.
4.  Change the default username and password to something secure.
5.  Check "Bypass authentication for clients on localhost".

### 2. Connect Prowlarr to qBittorrent
Prowlarr manages your indexers and sends downloads to the client.
1.  Open **Prowlarr** (`http://<SERVER-IP>:9696`).
2.  Go to **Settings > Download Clients**.
3.  Click **+** and select **qBittorrent**.
4.  **Host:** `localhost` (Do NOT use the container name).
5.  **Port:** `8091`.
6.  **Username/Password:** Enter the credentials you set in Step 1.
7.  Test and Save.

### 3. Connect Prowlarr to Sonarr & Radarr
Prowlarr will automatically sync your indexers to Sonarr and Radarr.
1.  Open **Sonarr** (`http://<SERVER-IP>:8989`) and **Radarr** (`http://<SERVER-IP>:7878`) in new tabs.
2.  In both apps, go to **Settings > General** and copy the **API Key**.
3.  Go back to **Prowlarr > Settings > Apps**.
4.  Click **+** and select **Sonarr** (or Radarr).
5.  **Prowlarr Server:** `http://localhost:9696`
6.  **Sonarr Server:** `http://localhost:8989`
7.  **ApiKey:** Paste the key you copied.
8.  Test and Save.

*(Repeat for Radarr using port `7878`).*

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