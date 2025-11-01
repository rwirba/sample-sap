#!/bin/bash
set -euxo pipefail

echo "[INFO] Starting sapuser setup ..."

# --- Ensure dependencies ---
sudo dnf -y update
sudo dnf -y install git python3-pip podman podman-docker buildah skopeo runc shadow-utils util-linux-user systemd dbus

# --- Start dbus/logind if not running ---
sudo systemctl start dbus || true
sudo systemctl start systemd-logind || true

# --- Clean any broken sapuser entries ---
sudo sed -i '/^sapuser:/d' /etc/passwd || true
sudo sed -i '/^sapuser:/d' /etc/shadow || true
sudo sed -i '/^sapuser:/d' /etc/group  || true

# --- Create sapuser safely ---
if ! id sapuser &>/dev/null; then
  sudo useradd -m -s /bin/bash sapuser
fi

echo 'sapuser ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/sapuser >/dev/null
sudo chmod 440 /etc/sudoers.d/sapuser

# --- Configure subuid/subgid ---
if ! grep -q "^sapuser:" /etc/subuid; then
  echo "sapuser:100000:65536" | sudo tee -a /etc/subuid >/dev/null
fi
if ! grep -q "^sapuser:" /etc/subgid; then
  echo "sapuser:100000:65536" | sudo tee -a /etc/subgid >/dev/null
fi

# --- Enable lingering ---
sudo loginctl enable-linger sapuser || true

# --- Prepare rootless Podman config ---
sudo -u sapuser mkdir -p /home/sapuser/.config/containers /home/sapuser/.local/share/containers
cat <<EOC | sudo tee /home/sapuser/.config/containers/containers.conf >/dev/null
[engine]
runtime = "runc"
events_logger = "journald"
cgroup_manager = "cgroupfs"
EOC
sudo chown -R sapuser:sapuser /home/sapuser/.config /home/sapuser/.local

# --- Prepare data directory ---
sudo mkdir -p /data/hxe
sudo chown -R sapuser:sapuser /data
sudo chmod -R 775 /data

# --- Configure environment ---
cat <<'EOC' | sudo tee -a /home/sapuser/.bashrc >/dev/null
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$${XDG_RUNTIME_DIR}/bus
export PATH=/usr/bin:$PATH
alias podman='podman --cgroup-manager=cgroupfs'
EOC
sudo chown sapuser:sapuser /home/sapuser/.bashrc

# --- Install Ansible ---
sudo pip3 install --upgrade pip
sudo pip3 install ansible
sudo ansible-galaxy collection install community.general ansible.posix

# --- Verify user ---
id sapuser
getent passwd sapuser
echo "[✅ SUCCESS] sapuser is created and ready for rootless Podman."
