# Servarr VPN Stack

A fully automated, privacy-focused media stack running on Docker. This stack routes all traffic (including media metadata requests) through a Gluetun VPN tunnel, ensuring your IP address is never exposed.

## Features

* **VPN-First Design:** All containers (Radarr, Sonarr, Prowlarr, qBittorrent, Jellyfin) are routed through `gluetun`. If the VPN drops, the internet connection for these apps dies instantly (Kill Switch).
* **Automated Setup:** Includes an interactive `install.sh` script to configure user permissions, directories, and networks automatically.
* **Atomic Moves:** Optimized Docker volume mapping for instant file moves and hardlinking (no duplicate files).
* **FlareSolverr:** Built-in support to bypass Cloudflare protection on indexers.

---

## Installation (Automated)

This method is recommended for Linux/macOS users.

### 1. Clone the Repository
```bash
git clone https://github.com/jruxtapose/servarr-stack.git
cd servarr-stack
```

### 2. Run the Installer
The installer will check for Docker, detect your local network subnet (required for WebUI access), and generate your `.env` configuration file.

```bash
chmod +x install.sh
./install.sh
```

Follow the on-screen prompts. You will need:
* **Your VPN Credentials:**
    * **Important:** Do not guess these! Most providers (ProtonVPN, Mullvad, PIA, etc.) require specific **Service Credentials** or **Config Files** that are different from your website login.
    * **Find your provider here:** [Gluetun Providers List](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers)
    * Click your provider in that list and follow the specific instructions to get the required username/password/variables ready.
* **Your preferred media storage path.**

### 3. Start the Stack
If you didn't choose to start it during the install script:
```bash
cd servarr
docker compose up -d
```

---

## Installation (Manual / Windows)

If you cannot run the `.sh` script (e.g., you are on Windows) or prefer to configure everything manually, follow these steps.

> **⚠️ Windows Storage Warning:**
> Docker on Windows often has limited support for file system **hardlinks** (atomic moves) compared to Linux.
>
> Consequently, Sonarr and Radarr may be forced to **copy** files from your downloads folder to your media folder rather than linking them. If you plan to seed your torrents, this will result in **data duplication** (the file will exist in both locations), which will use **double the disk space**.

### 1. Prepare Directory
Navigate into the `servarr` subdirectory where the configuration files are located.
```bash
cd servarr
```

### 2. Configure Environment Variables
1. Rename `.env.example` to `.env`.
2. Open `.env` in a text editor (Notepad, VS Code, Nano).
3. Fill in the required values:
   * **PUID/PGID:** On Linux, run `id` to find yours. On Windows, these can usually be left as default (1000) or removed if not needed.
   * **MEDIA_ROOT:** The absolute path to your media folder (e.g., `C:\Users\Name\Media` or `/home/user/media`).
   * **LOCAL_SUBNET:** Your local network range (e.g., `192.168.1.0/24`). This is required to access the WebUIs.
   * **VPN Credentials:** Enter your VPN provider, username, and password.
     * **Important:** Visit the [Gluetun Providers List](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers). Find your provider and follow the instructions to generate your **Service Credentials**. Do not use your regular email login unless explicitly told to do so.

### 3. Create Directories
Manually create the configuration subfolders to ensure permissions are correct:
```text
/config/jellyfin
/config/prowlarr
/config/radarr
/config/sonarr
/config/qbittorrent
```

### 4. Start the Stack
Open a terminal or command prompt in the `servarr` folder and run:
```bash
docker compose up -d
```

---

## Configuration Guide (Critical Steps)

Once the stack is running, you must configure the applications to talk to each other. Access the WebUIs using your server's IP address (e.g., `http://192.168.1.50:PORT` or `http://localhost:PORT`).

### 1. qBittorrent (Port 8091)
* **Login:** Default username is `admin`. Default password is usually `adminadmin` (check logs if uncertain).
* **Go to:** Tools -> Options -> Downloads.
* **Default Save Path:** Set this **EXACTLY** to:  
    `/data/torrents`
* **Keep Incomplete Torrents in:** Checked.
    `/data/torrents/.incomplete`
* **Go to:** Tools -> Options -> Web UI.
* **Bypass authentication for clients on localhost:** Check this box (Simplifies linking to Sonarr/Radarr).

### 2. Prowlarr (Port 9696)
* **Add Flaresolverr:**
    1.  Go to Settings -> Indexers -> Options.
    2.  Add a generic **FlareSolverr** tag (e.g., `flaresolverr`).
    3.  Go to Settings -> Indexers -> Proxies.
    4.  Click `+` -> FlareSolverr.
    5.  **Host:** `http://localhost:8191` (Since they share the VPN network, they talk on localhost).
    6.  **Tags:** `flaresolverr`.
    7.  Save.
* **Connect to Apps:**
    1.  Go to Settings -> Apps.
    2.  Click `+` -> **Radarr**.
    3.  **Prowlarr Server:** `http://localhost:9696`
    4.  **Radarr Server:** `http://localhost:7878`
    5.  **ApiKey:** Get this from Radarr (Settings -> General).
    6.  Repeat for **Sonarr** (Port `8989`).

### 3. Sonarr (Port 8989) & Radarr (Port 7878)
The steps are identical for both.

* **Media Management:**
    1.  Go to Settings -> Media Management.
    2.  Check **Show Advanced**.
    3.  **Hardlinks:** Checked (Essential for saving space).
    4.  **Root Folders:** Add `/data/media/tv` (for Sonarr) or `/data/media/movies` (for Radarr).
* **Download Client:**
    1.  Go to Settings -> Download Clients.
    2.  Click `+` -> **qBittorrent**.
    3.  **Name:** `Gluetun-qBit`
    4.  **Host:** `localhost`
    5.  **Port:** `8091`
    6.  **Username/Password:** Your qBittorrent login.
    7.  **Test** and **Save**.

### 4. Jellyfin (Port 8096)
1.  Walk through the initial setup wizard.
2.  **Add Media Library:**
    * **Content type:** Movies
    * **Folders:** `/data/media/movies`
3.  **Add Media Library:**
    * **Content type:** Shows
    * **Folders:** `/data/media/tv`
4.  **Connect to Sonarr/Radarr (Optional):**
    * You can set up webhooks in Sonarr/Radarr to notify Jellyfin on new downloads to update the library instantly.
    * In Sonarr: Settings -> Connect -> `+` -> Jellyfin.
    * Host: