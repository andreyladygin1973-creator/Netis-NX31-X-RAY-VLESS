# Netis NX31: Transparent VLESS/Reality Tunnel Setup

A lightweight, memory-optimized OpenWrt setup script designed to create a transparent proxy tunnel using Xray (VLESS + Reality) and Redsocks. 

This project was specifically built and optimized for the **Netis NX31** router (MediaTek MT7981, 256MB RAM, OpenWrt 21.02, ARM64), but the core concepts can be adapted for other low-spec OpenWrt devices.

## 🌟 Key Features

* **Transparent Proxy:** Redirects all TCP traffic from LAN clients through Xray without requiring any client-side configuration.
* **Anti-QUIC Leak Protection:** Automatically blocks UDP 443 (QUIC) for LAN clients. This forces browsers (Chrome, Firefox, Opera) to fall back to TCP 443, preventing IP leaks and ensuring Cloudflare routes traffic through the correct proxy PoP.
* **DNS over HTTPS (DoH):** Uses `https-dns-proxy` and cleans up stock vendor DNS bugs (removes the dead `127.0.0.1#5053` fallback) to prevent DNS leaks.
* **Low RAM Optimized:** Runs the Go-based Xray binary with `GOMEMLIMIT=50MiB` and `GOGC=20` to prevent OOM (Out-Of-Memory) crashes on 256MB routers.
* **Custom CGI Web UI:** Provides a lightweight `/cgi-bin/vless` interface to update VLESS links, manage subscriptions, and restart the service without rebooting the router.

## ⚠️ Disclaimer & Compatibility

**This script is highly customized for the Netis NX31 (or identical clones).** 
Do not run it blindly on other routers. If you are using a different device or a standard OpenWrt build, you **must** adapt the following:
1. **WAN Interface:** Change `eth1` to your actual WAN interface (e.g., `wan`, `pppoe-wan`) inside `firewall.user`.
2. **Architecture:** Ensure the `xray` binary matches your CPU architecture (this repo assumes `aarch64`).
3. **Web UI:** The HTML/JS files are tailored for the stock Netis web interface. If you use LuCI, the UI integration will not work out of the box.

## 📋 Prerequisites

To automate the deployment, this project uses official command-line tools from **PuTTY**: `plink.exe` (for SSH) and `pscp.exe` (for SFTP file transfer).

* **Automatic:** You don't need to download them manually. The `nx31.bat` script will automatically fetch them from the [official PuTTY website](https://www.putty.org/) when you run it for the first time.
* **Manual (if auto-download fails):** If your PC blocks PowerShell from downloading files, download `plink.exe` and `pscp.exe` (64-bit) manually and place them in the same folder as `nx31.bat`.

*(Note: These executables are intentionally excluded from this repository via `.gitignore` for security and size reasons).*

## 🚀 How to Use (Windows)

1. **Get your VLESS link:** Ensure you have a working VLESS Reality URI.
2. **Configure the script:** Open `nx31.bat` in a text editor and replace the `DIRECT_URL` variable with your actual VLESS link.
3. **Connect to the router:** Connect your PC to the Netis NX31 router via LAN or Wi-Fi.
4. **Run the installer:** Double-click `nx31.bat`. 
   * *(First run)* The script will automatically download `plink.exe` and `pscp.exe` if they are missing.
   * The script will then configure `opkg` repositories, upload all necessary scripts/configs, run the setup (install packages, configure iptables, set up DoH), and reboot the router.
5. **Access the UI:** After 2–3 minutes, open your browser and go to `http://192.168.1.1/vless.html` to view the status or update your VLESS link.

## 📁 Project Structure

* `nx31.bat` — The main Windows installer script (automates SSH/SFTP and downloads dependencies).
* `setup.sh` — The core router setup script (runs on OpenWrt).
* `firewall.user` — Persistent `iptables` rules for NAT, transparent proxy, and QUIC blocking.
* `vless.cgi` / `vless.html` — Lightweight CGI web interface for management.
* `xray-updater.sh` / `xray-watchdog.sh` — Background scripts to update configs and keep Xray alive.
* `config.template.json` — The Xray configuration template.

## 🛡️ Security

This repository uses a strict `.gitignore` to prevent the accidental upload of:
* Your `urls.txt` (which contains your private VLESS UUID and server IP).
* Executables (`plink.exe`, `pscp.exe`).
* The heavy Xray binary.

**Never commit your real VLESS links to a public repository.**
## ☕ Support the Project / Поддержать проект

This project is completely free and open-source. If this script saved you hours of setup time or helped bypass DPI, consider supporting its further development! 
*(Проект создавался на чистом энтузиазме. Если скрипт сэкономил Вам время, вы можете отблагодарить автора)*

[![Donate via YooMoney](https://img.shields.io/badge/Donate-YooMoney-purple?style=for-the-badge)](https://yoomoney.ru/to/410011080637190/1000)
[![USDT TRC-20](https://img.shields.io/badge/USDT%20TRC--20-Wallet-green?style=for-the-badge)](https://tronscan.org/#/address/TL8hBVPC3v99qfiwP6xmFN38kQHxpPXMw7)

**YooMoney:** [https://yoomoney.ru/to/410011080637190/1000](https://yoomoney.ru/to/410011080637190/1000)

**Crypto (USDT TRC-20):** `TL8hBVPC3v99qfiwP6xmFN38kQHxpPXMw7`

## 📄 License
This project is licensed under the MIT License.