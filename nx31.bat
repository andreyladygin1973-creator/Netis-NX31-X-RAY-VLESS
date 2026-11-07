@echo off
setlocal
chcp 65001 >nul
color 0A

set ROUTER_IP=192.168.1.1
set USER=admin
set PASS=Test1234
set ROUTER=%USER%@%ROUTER_IP%

REM ====================================================================
REM  ВАЖНО: без параметра support-x25519mlkem768=true,
REM  иначе будет "remote error: tls: illegal parameter"
REM ====================================================================
set "SUB_URL="
set "DIRECT_URL=vless://YOUR_UUID_HERE@YOUR_SERVER_IP:443?encryption=none&...#MyServer"

set PLINK=%~dp0plink.exe
set PSCP=%~dp0pscp.exe

cd /d "%~dp0"

echo ===================================================
echo   NX31 INSTALLER: Xray + VLESS + DoH
echo ===================================================
echo Please wait (3-5 minutes)...

echo [0/6] Checking connection and host key...
echo [!] IF THIS IS A NEW ROUTER: type "y" and press Enter.
"%PLINK%" -ssh -l %USER% -pw %PASS% %ROUTER_IP% "exit" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Cannot connect. Check IP/password, or manually accept the host key.
    pause & exit /b 1
)

echo [1/6] Pinging router...
ping -n 2 %ROUTER_IP% > nul
if errorlevel 1 (
    echo ERROR: Router %ROUTER_IP% not responding.
    pause & exit /b 1
)

echo [2/6] Repos + packages (SFTP + https-dns-proxy)...
"%PLINK%" -batch -pw %PASS% %ROUTER% "echo 'src/gz openwrt_base https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/base' > /etc/opkg/distfeeds.conf"
"%PLINK%" -batch -pw %PASS% %ROUTER% "echo 'src/gz openwrt_luci https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/luci' >> /etc/opkg/distfeeds.conf"
"%PLINK%" -batch -pw %PASS% %ROUTER% "echo 'src/gz openwrt_packages https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/packages' >> /etc/opkg/distfeeds.conf"
"%PLINK%" -batch -pw %PASS% %ROUTER% "echo 'src/gz openwrt_routing https://downloads.openwrt.org/releases/21.02.7/packages/aarch64_cortex-a53/routing' >> /etc/opkg/distfeeds.conf"
"%PLINK%" -batch -pw %PASS% %ROUTER% "opkg update && opkg install openssh-sftp-server https-dns-proxy"

echo [2.5/6] Cleaning old artifacts to free flash...
"%PLINK%" -batch -pw %PASS% %ROUTER% "rm -f /etc/xray/xray.gz /etc/xray/xray.xz /etc/xray/xray; rm -rf /tmp/opkg-lists/*; rm -f /tmp/xray /tmp/*.dat /tmp/*.ipk; echo 'Cleanup OK.'"

echo [3/6] Uploading files...
(
echo "SUB_URL=%SUB_URL%"
echo "DIRECT_URL=%DIRECT_URL%"
) > urls.txt

"%PSCP%" -batch -pw %PASS% xray config.template.json xray-updater.sh xray-watchdog.sh setup.sh header.js urls.txt %ROUTER%:/tmp/
"%PSCP%" -batch -pw %PASS% vless.html vless.cgi %ROUTER%:/tmp/

echo [4/6] Fixing Windows line endings...
"%PLINK%" -batch -pw %PASS% %ROUTER% "sed -i 's/\r//' /tmp/setup.sh /tmp/xray-updater.sh /tmp/xray-watchdog.sh /tmp/config.template.json /tmp/vless.html /tmp/vless.cgi /tmp/header.js /tmp/urls.txt"

echo [5/6] Running setup on router...
"%PLINK%" -batch -pw %PASS% %ROUTER% "sh /tmp/setup.sh"

echo [6/6] Rebooting...
"%PLINK%" -batch -pw %PASS% %ROUTER% "reboot"

echo.
echo ===================================================
echo   DONE. Wait 2-3 minutes, then check:
echo     http://192.168.1.1/vless.html
echo ===================================================
pause