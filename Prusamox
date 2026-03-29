#!/usr/bin/env bash

# ==============================================================

# PrusaSlicer LXC - Proxmox Helper Script

# Run this directly on your Proxmox HOST shell (not inside a VM)

# 

# Usage:

# bash -c “$(curl -fsSL https://raw.githubusercontent.com/YOUR-USER/YOUR-REPO/main/prusaslicer-proxmox.sh)”

# 

# ==============================================================

set -e

# –––––––––––––––––––––––––––––––

# Colour helpers

# –––––––––––––––––––––––––––––––

YW=$(echo “\033[33m”)
GN=$(echo “\033[1;92m”)
RD=$(echo “\033[01;31m”)
CL=$(echo “\033[m”)
BFR=”\r\033[K”
HOLD=” “
CM=”${GN}✓${CL}”
CROSS=”${RD}✗${CL}”

msg_info()  { echo -ne “ ${HOLD} ${YW}${1}…${CL}”; }
msg_ok()    { echo -e “${BFR} ${CM} ${GN}${1}${CL}”; }
msg_error() { echo -e “${BFR} ${CROSS} ${RD}${1}${CL}”; exit 1; }

# –––––––––––––––––––––––––––––––

# Defaults - edit these if you want different values

# –––––––––––––––––––––––––––––––

CT_ID=$(pvesh get /cluster/nextid)   # Next available CT ID
CT_NAME=“prusaslicer”
CT_CORES=2
CT_RAM=2048
CT_DISK=20
CT_BRIDGE=“vmbr0”
CT_STORAGE=“local-lvm”               # Change to your storage name e.g. local, local-zfs
CT_TEMPLATE=“local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst”
VNC_PASS=“prusa3d”
USER_PASS=“prusa”
NOVNC_PORT=6080

# –––––––––––––––––––––––––––––––

# Header

# –––––––––––––––––––––––––––––––

echo -e “\n

-----

|  _ \ _ __ _   _ ___  / ***|| (*) ___ ___ _ __
| |*) | ’**| | | / **| _** | | |/ **/ _ \ ’**|
|  **/| |  | |*| _* \  ***) | | | (*|  __/ |
|*|   |*|   _*,*|***/ |_***/|*|*|_**_**|*|

Proxmox LXC Installer
Container ID : ${CT_ID}
Name         : ${CT_NAME}
Cores        : ${CT_CORES}
RAM          : ${CT_RAM}MB
Disk         : ${CT_DISK}GB
Bridge       : ${CT_BRIDGE}
Storage      : ${CT_STORAGE}
noVNC Port   : ${NOVNC_PORT}
“

read -r -p “ Proceed with installation? [y/N] “ prompt
if [[ ! “${prompt}” =~ ^[Yy]$ ]]; then
echo “Aborted.”
exit 0
fi

# –––––––––––––––––––––––––––––––

# Check template exists, download if not

# –––––––––––––––––––––––––––––––

msg_info “Checking Ubuntu 22.04 template”
TEMPLATE_FILE=$(basename “$CT_TEMPLATE” | sed ‘s/local:vztmpl///’)
if ! pveam list local | grep -q “ubuntu-22.04”; then
msg_info “Downloading Ubuntu 22.04 template”
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst ||   
msg_error “Failed to download template. Check storage and connectivity.”
fi
msg_ok “Template ready”

# –––––––––––––––––––––––––––––––

# Create the LXC container

# –––––––––––––––––––––––––––––––

msg_info “Creating LXC container ${CT_ID}”
pct create “${CT_ID}” “${CT_TEMPLATE}”   
–hostname “${CT_NAME}”   
–cores “${CT_CORES}”   
–memory “${CT_RAM}”   
–rootfs “${CT_STORAGE}:${CT_DISK}”   
–net0 name=eth0,bridge=”${CT_BRIDGE}”,ip=dhcp   
–unprivileged 0   
–features nesting=1   
–onboot 1   
–start 0   
–ostype ubuntu
msg_ok “Container ${CT_ID} created”

# –––––––––––––––––––––––––––––––

# Start container

# –––––––––––––––––––––––––––––––

msg_info “Starting container”
pct start “${CT_ID}”
sleep 5
msg_ok “Container started”

# –––––––––––––––––––––––––––––––

# Wait for network

# –––––––––––––––––––––––––––––––

msg_info “Waiting for network”
for i in $(seq 1 20); do
if pct exec “${CT_ID}” – ping -c1 -W1 8.8.8.8 &>/dev/null; then
break
fi
sleep 2
done
msg_ok “Network ready”

# –––––––––––––––––––––––––––––––

# Push and run the inner setup script inside the container

# –––––––––––––––––––––––––––––––

msg_info “Injecting setup script into container”

pct exec “${CT_ID}” – bash -c “cat > /root/inner-setup.sh << ‘INNEREOF’
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo ‘[1/7] Updating system…’
apt-get update -qq && apt-get upgrade -y -qq

echo ‘[2/7] Installing packages…’
apt-get install -y -qq   
wget curl libfuse2 openbox   
tigervnc-standalone-server novnc websockify   
xterm dbus-x11 x11-xserver-utils

echo ‘[3/7] Creating prusa user…’
if ! id prusa &>/dev/null; then
useradd -m -s /bin/bash prusa
echo ‘prusa:${USER_PASS}’ | chpasswd
fi

echo ‘[4/7] Downloading PrusaSlicer…’
PRUSA_URL=$(curl -s https://api.github.com/repos/prusa3d/PrusaSlicer/releases/latest   
| grep browser_download_url   
| grep linux-x64   
| grep .AppImage   
| head -1   
| cut -d ‘"’ -f 4)

if [ -z "$PRUSA_URL" ]; then
PRUSA_URL="https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.8.1/PrusaSlicer-2.8.1+linux-x64-GTK3-202409181427.AppImage"
fi

wget -q –show-progress -O /opt/prusaslicer.AppImage "$PRUSA_URL"
chmod +x /opt/prusaslicer.AppImage

cat > /usr/local/bin/prusaslicer << ‘EOF’
#!/bin/bash
/opt/prusaslicer.AppImage –appimage-extract-and-run "$@"
EOF
chmod +x /usr/local/bin/prusaslicer

echo ‘[5/7] Configuring VNC…’
mkdir -p /home/prusa/.vnc
echo ‘${VNC_PASS}’ | vncpasswd -f > /home/prusa/.vnc/passwd
chmod 600 /home/prusa/.vnc/passwd

cat > /home/prusa/.vnc/xstartup << ‘EOF’
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
openbox-session &
sleep 2
/opt/prusaslicer.AppImage –appimage-extract-and-run
EOF
chmod +x /home/prusa/.vnc/xstartup

mkdir -p /home/prusa/.config/openbox
mkdir -p /home/prusa/prints
chown -R prusa:prusa /home/prusa/.vnc /home/prusa/.config /home/prusa/prints

echo ‘[6/7] Creating systemd services…’

cat > /etc/systemd/system/vncserver@.service << ‘EOF’
[Unit]
Description=TigerVNC server
After=network.target

[Service]
Type=forking
User=prusa
Group=prusa
WorkingDirectory=/home/prusa
PIDFile=/home/prusa/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i -geometry 1600x900 -depth 24 -localhost yes
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/novnc.service << ‘EOF’
[Unit]
Description=noVNC Web Client
After=network.target vncserver@1.service
Requires=vncserver@1.service

[Service]
Type=simple
User=prusa
ExecStart=/usr/bin/websockify –web=/usr/share/novnc/ ${NOVNC_PORT} localhost:5901
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vncserver@1.service novnc.service
systemctl start vncserver@1.service
sleep 3
systemctl start novnc.service

echo ‘[7/7] Done.’
INNEREOF
chmod +x /root/inner-setup.sh”

msg_ok “Script injected”

msg_info “Running setup inside container (this will take a few minutes)”
pct exec “${CT_ID}” – bash /root/inner-setup.sh
msg_ok “Setup complete”

# –––––––––––––––––––––––––––––––

# Get container IP and print summary

# –––––––––––––––––––––––––––––––

sleep 2
CT_IP=$(pct exec “${CT_ID}” – hostname -I | awk ‘{print $1}’)

echo -e “\n
${GN}================================================
PrusaSlicer is ready!
================================================${CL}

Open in your browser:

${YW}http://${CT_IP}:${NOVNC_PORT}/vnc.html${CL}

VNC password : ${YW}${VNC_PASS}${CL}
Linux user   : ${YW}prusa / ${USER_PASS}${CL}
Container ID : ${YW}${CT_ID}${CL}

Print files  : /home/prusa/prints
(Add a Proxmox bind mount here to persist your files)

${RD} Change default passwords after first login!${CL}

To add persistent file storage, run on this host:
echo ‘mp0: /your/nas/path,mp=/home/prusa/prints’ >> /etc/pve/lxc/${CT_ID}.conf
pct reboot ${CT_ID}

================================================
“
