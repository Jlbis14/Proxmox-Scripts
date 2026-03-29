#!/usr/bin/env bash
set -e

YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD=" "
CM="${GN}+${CL}"
CROSS="${RD}x${CL}"

msg_info()  { echo -ne " ${HOLD} ${YW}${1}...${CL}"; }
msg_ok()    { echo -e "${BFR} ${CM} ${GN}${1}${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}${1}${CL}"; exit 1; }

CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="prusaslicer"
CT_CORES=2
CT_RAM=2048
CT_DISK=20
CT_BRIDGE="vmbr0"
CT_STORAGE="local-lvm"
CT_TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
VNC_PASS="prusa3d"
USER_PASS="prusa"
NOVNC_PORT=6080

echo ""
echo "PrusaSlicer LXC Installer"
echo "Container ID : ${CT_ID}"
echo "Name         : ${CT_NAME}"
echo "Cores        : ${CT_CORES}"
echo "RAM          : ${CT_RAM}MB"
echo "Disk         : ${CT_DISK}GB"
echo "Bridge       : ${CT_BRIDGE}"
echo "Storage      : ${CT_STORAGE}"
echo "noVNC Port   : ${NOVNC_PORT}"
echo ""

read -r -p "Proceed with installation? [y/N] " prompt
if [[ ! "${prompt}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

msg_info "Checking Ubuntu 22.04 template"
if ! pveam list local | grep -q "ubuntu-22.04"; then
  msg_info "Downloading Ubuntu 22.04 template"
  pveam update
  pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst || msg_error "Failed to download template"
fi
msg_ok "Template ready"

msg_info "Creating LXC container ${CT_ID}"
pct create "${CT_ID}" "${CT_TEMPLATE}" \
  --hostname "${CT_NAME}" \
  --cores "${CT_CORES}" \
  --memory "${CT_RAM}" \
  --rootfs "${CT_STORAGE}:${CT_DISK}" \
  --net0 name=eth0,bridge="${CT_BRIDGE}",ip=dhcp \
  --unprivileged 0 \
  --features nesting=1 \
  --onboot 1 \
  --start 0 \
  --ostype ubuntu
msg_ok "Container ${CT_ID} created"

msg_info "Starting container"
pct start "${CT_ID}"
sleep 5
msg_ok "Container started"

msg_info "Waiting for network"
for i in $(seq 1 20); do
  if pct exec "${CT_ID}" -- ping -c1 -W1 8.8.8.8 &>/dev/null; then
    break
  fi
  sleep 2
done
msg_ok "Network ready"

msg_info "Injecting setup script into container"

pct exec "${CT_ID}" -- bash -c 'cat > /root/inner-setup.sh << '"'"'INNEREOF'"'"'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Updating system..."
apt-get update -qq && apt-get upgrade -y -qq

echo "[2/7] Installing packages..."
apt-get install -y -qq wget curl libfuse2 openbox tigervnc-standalone-server novnc websockify xterm dbus-x11 x11-xserver-utils

echo "[3/7] Creating prusa user..."
if ! id prusa &>/dev/null; then
  useradd -m -s /bin/bash prusa
  echo "prusa:prusa" | chpasswd
fi

echo "[4/7] Downloading PrusaSlicer..."
PRUSA_URL=$(curl -s https://api.github.com/repos/prusa3d/PrusaSlicer/releases/latest | grep browser_download_url | grep linux-x64 | grep AppImage | head -1 | cut -d '"' -f 4)
if [ -z "$PRUSA_URL" ]; then
  PRUSA_URL="https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.8.1/PrusaSlicer-2.8.1+linux-x64-GTK3-202409181427.AppImage"
fi
wget -q -O /opt/prusaslicer.AppImage "$PRUSA_URL"
chmod +x /opt/prusaslicer.AppImage

echo "[5/7] Configuring VNC..."
mkdir -p /home/prusa/.vnc
echo "prusa3d" | vncpasswd -f > /home/prusa/.vnc/passwd
chmod 600 /home/prusa/.vnc/passwd

cat > /home/prusa/.vnc/xstartup << EOF2
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
openbox-session &
sleep 2
/opt/prusaslicer.AppImage --appimage-extract-and-run
EOF2
chmod +x /home/prusa/.vnc/xstartup

mkdir -p /home/prusa/.config/openbox
mkdir -p /home/prusa/prints
chown -R prusa:prusa /home/prusa/.vnc /home/prusa/.config /home/prusa/prints

echo "[6/7] Creating systemd services..."

cat > /etc/systemd/system/vncserver@.service << EOF2
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
EOF2

cat > /etc/systemd/system/novnc.service << EOF2
[Unit]
Description=noVNC Web Client
After=network.target vncserver@1.service
Requires=vncserver@1.service

[Service]
Type=simple
User=prusa
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 localhost:5901
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable vncserver@1.service novnc.service
systemctl start vncserver@1.service
sleep 3
systemctl start novnc.service

echo "[7/7] Done."
INNEREOF
chmod +x /root/inner-setup.sh'

msg_ok "Script injected"

msg_info "Running setup inside container (this will take a few minutes)"
pct exec "${CT_ID}" -- bash /root/inner-setup.sh
msg_ok "Setup complete"

sleep 2
CT_IP=$(pct exec "${CT_ID}" -- hostname -I | awk '{print $1}')

echo ""
echo "================================================"
echo " PrusaSlicer is ready!"
echo "================================================"
echo ""
echo " Open in your browser:"
echo " http://${CT_IP}:${NOVNC_PORT}/vnc.html"
echo ""
echo " VNC password : prusa3d"
echo " Linux user   : prusa / prusa"
echo " Container ID : ${CT_ID}"
echo ""
echo " Change default passwords after first login!"
echo "================================================"
