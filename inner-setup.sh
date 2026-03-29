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

echo "[4/7] Downloading PrusaSlicer 2.8.1..."
PRUSA_URL="https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.8.1/PrusaSlicer-2.8.1+linux-x64-GTK3-202409181427.AppImage"
wget -q --show-progress -O /opt/prusaslicer.AppImage "$PRUSA_URL"
chmod +x /opt/prusaslicer.AppImage
echo "PrusaSlicer downloaded."

echo "[5/7] Configuring VNC..."
mkdir -p /home/prusa/.vnc
echo "prusa3d" | vncpasswd -f > /home/prusa/.vnc/passwd
chmod 600 /home/prusa/.vnc/passwd

cat > /home/prusa/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
openbox-session &
sleep 2
/opt/prusaslicer.AppImage --appimage-extract-and-run
EOF
chmod +x /home/prusa/.vnc/xstartup

mkdir -p /home/prusa/.config/openbox
mkdir -p /home/prusa/prints
chown -R prusa:prusa /home/prusa/.vnc /home/prusa/.config /home/prusa/prints

echo "[6/7] Creating systemd services..."

cat > /etc/systemd/system/vncserver@.service << 'EOF'
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

cat > /etc/systemd/system/novnc.service << 'EOF'
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
EOF

systemctl daemon-reload
systemctl enable vncserver@1.service novnc.service
systemctl start vncserver@1.service
sleep 3
systemctl start novnc.service

echo "[7/7] Done."
