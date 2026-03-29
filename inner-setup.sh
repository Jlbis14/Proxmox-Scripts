#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Updating system..."
apt-get update -qq
apt-get upgrade -y -qq

echo "[2/8] Setting up locale..."
apt-get install -y -qq locales
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo "[3/8] Installing desktop and VNC..."
apt-get install -y -qq \
  openbox \
  tigervnc-standalone-server \
  novnc \
  websockify \
  xterm \
  dbus-x11 \
  x11-xserver-utils \
  x11-utils \
  libglu1-mesa \
  libegl1 \
  libgl1-mesa-glx \
  libgles2 \
  libwebkit2gtk-4.0-37 \
  libfuse2

echo "[4/8] Installing Flatpak..."
apt-get install -y -qq flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "[5/8] Installing PrusaSlicer from Flathub..."
flatpak install -y flathub com.prusa3d.PrusaSlicer

echo "[6/8] Creating prusa user..."
if ! id prusa &>/dev/null; then
  useradd -m -s /bin/bash prusa
  echo "prusa:prusa" | chpasswd
  usermod -aG sudo prusa
fi

echo "[7/8] Configuring VNC..."
mkdir -p /home/prusa/.vnc
echo "prusa3d" | vncpasswd -f > /home/prusa/.vnc/passwd
chmod 600 /home/prusa/.vnc/passwd

cat > /home/prusa/.vnc/xstartup << 'EOF'
#!/bin/bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
openbox &
sleep 2
flatpak run com.prusa3d.PrusaSlicer
EOF
chmod +x /home/prusa/.vnc/xstartup

mkdir -p /home/prusa/.config/openbox
mkdir -p /home/prusa/prints
chown -R prusa:prusa /home/prusa

echo "[8/8] Setting up auto-start..."

# Create a startup script that runs as prusa user
cat > /usr/local/bin/start-prusaslicer.sh << 'EOF'
#!/bin/bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Wait for system to settle
sleep 5

# Kill any stale VNC locks
su - prusa -c "vncserver -kill :1 > /dev/null 2>&1" || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# Start VNC as prusa user
su - prusa -c "vncserver :1 -geometry 1600x900 -depth 24"

# Wait for VNC to be ready
sleep 5

# Start noVNC
websockify --web=/usr/share/novnc/ 6080 localhost:5901 --daemon --log-file=/var/log/novnc.log

echo "PrusaSlicer stack started."
EOF
chmod +x /usr/local/bin/start-prusaslicer.sh

# Use rc.local for reliable LXC boot startup
cat > /etc/rc.local << 'EOF'
#!/bin/bash
/usr/local/bin/start-prusaslicer.sh &
exit 0
EOF
chmod +x /etc/rc.local

# Enable rc.local service
systemctl enable rc-local

# Start it now too
/usr/local/bin/start-prusaslicer.sh

echo ""
echo "Done! PrusaSlicer will start automatically on every boot."
