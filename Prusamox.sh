#!/usr/bin/env bash
set -e

INNER_URL="https://raw.githubusercontent.com/Jlbis14/Proxmox-Scripts/main/inner-setup.sh"

CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="prusaslicer"
CT_CORES=2
CT_RAM=2048
CT_DISK=20
CT_BRIDGE="vmbr0"
CT_STORAGE="local-lvm"
CT_TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
NOVNC_PORT=6080

SMB_SERVER="192.168.50.246"
SMB_SHARE="slicer"
SMB_USER="Bishop"
SMB_PASS="nm3raf9n!"
SMB_MOUNT="/mnt/share/slicer"

echo ""
echo "================================================"
echo " PrusaSlicer LXC Installer"
echo " Container ID : ${CT_ID}"
echo " Storage      : ${CT_STORAGE}"
echo " RAM          : ${CT_RAM}MB"
echo " Disk         : ${CT_DISK}GB"
echo " Print files  : ${SMB_MOUNT} (TrueNAS)"
echo "================================================"
echo ""
echo " NOTE: Edit CT_STORAGE if your storage is not"
echo " local-lvm (e.g. local-zfs, local, SSD etc)"
echo ""

read -r -p " Proceed? [y/N] " prompt
if [[ ! "${prompt}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "[1/6] Checking Ubuntu 22.04 template..."
if ! pveam list local 2>/dev/null | grep -q "ubuntu-22.04"; then
  echo "  Downloading template..."
  pveam update
  pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
fi
echo "  Template ready."

echo "[2/6] Mounting TrueNAS share on Proxmox host..."
apt-get install -y -qq cifs-utils
mkdir -p "${SMB_MOUNT}"
if ! mountpoint -q "${SMB_MOUNT}"; then
  mount -t cifs "//${SMB_SERVER}/${SMB_SHARE}" "${SMB_MOUNT}" \
    -o username="${SMB_USER}",password="${SMB_PASS}",uid=100000,gid=100000,file_mode=0775,dir_mode=0775
  echo "  Share mounted at ${SMB_MOUNT}"
else
  echo "  Share already mounted."
fi

# Add to fstab for persistence across Proxmox reboots
FSTAB_ENTRY="//${SMB_SERVER}/${SMB_SHARE} ${SMB_MOUNT} cifs username=${SMB_USER},password=${SMB_PASS},uid=100000,gid=100000,file_mode=0775,dir_mode=0775,_netdev 0 0"
if ! grep -q "${SMB_SERVER}/${SMB_SHARE}" /etc/fstab; then
  echo "${FSTAB_ENTRY}" >> /etc/fstab
  echo "  Added to /etc/fstab for persistence."
fi

echo "[3/6] Creating container ${CT_ID}..."
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
echo "  Container created."

echo "[4/6] Adding shared print files folder to container..."
echo "mp0: ${SMB_MOUNT},mp=/home/prusa/prints" >> /etc/pve/lxc/${CT_ID}.conf
echo "  Bind mount added."

echo "[5/6] Starting container..."
pct start "${CT_ID}"
sleep 8
echo "  Container started."

echo "  Waiting for network..."
for i in $(seq 1 30); do
  if pct exec "${CT_ID}" -- ping -c1 -W1 8.8.8.8 &>/dev/null; then
    break
  fi
  sleep 2
done
echo "  Network ready."

echo "[6/6] Running setup inside container..."
echo "  Installing PrusaSlicer via Flatpak."
echo "  This will take 5-10 minutes. Please wait."
echo ""

pct exec "${CT_ID}" -- bash -c "apt-get install -y -qq curl wget 2>/dev/null && curl -fsSL ${INNER_URL} -o /root/inner-setup.sh && bash /root/inner-setup.sh"

CT_IP=$(pct exec "${CT_ID}" -- hostname -I | awk '{print $1}')

echo ""
echo "================================================"
echo " PrusaSlicer is ready!"
echo "================================================"
echo ""
echo " Open in your browser:"
echo ""
echo "   http://${CT_IP}:${NOVNC_PORT}/vnc.html"
echo ""
echo " VNC password  : prusa3d"
echo " Container ID  : ${CT_ID}"
echo " Container IP  : ${CT_IP}"
echo " Print files   : /home/prusa/prints"
echo "                 (mapped to your TrueNAS share)"
echo ""
echo " PrusaSlicer launches automatically on connect."
echo " Change VNC password after first login!"
echo "================================================"
echo ""
