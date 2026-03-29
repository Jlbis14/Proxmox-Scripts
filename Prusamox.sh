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
NOVNC_PORT=6080

INNER_SCRIPT_URL="https://raw.githubusercontent.com/Jlbis14/Proxmox-Scripts/main/inner-setup.sh"

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

msg_info "Downloading setup script into container"
pct exec "${CT_ID}" -- bash -c "curl -fsSL ${INNER_SCRIPT_URL} -o /root/inner-setup.sh && chmod +x /root/inner-setup.sh"
msg_ok "Script ready"

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
