#!/bin/bash
set -euxo pipefail

echo "[INFO] Setting up sapuser for rootless Podman..."

# --- Ensure D-Bus and logind are running ---
sudo systemctl start dbus || true
sudo systemctl start systemd-logind || true

# --- Clean any partial entries ---
sudo sed -i '/^sapuser:/d' /etc/passwd || true
sudo sed -i '/^sapuser:/d' /etc/shadow || true
sudo sed -i '/^sapuser:/d' /etc/group  || true

# --- Create sapuser safely ---
if ! id sapuser &>/dev/null; then
  sudo useradd -m -s /bin/bash sapuser
fi

# --- Allow passwordless sudo ---
echo 'sapuser ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/sapuser >/dev/null
sudo chmod 440 /etc/sudoers.d/sapuser

# --- Configure subuid/subgid for rootless Podman ---
if ! grep -q "^sapuser:" /etc/subuid; then
  echo "sapuser:100000:65536" | sudo tee -a /etc/subuid >/dev/null
fi
if ! grep -q "^sapuser:" /etc/subgid; then
  echo "sapuser:100000:65536" | sudo tee -a /etc/subgid >/dev/null
fi

# --- Enable lingering so rootless services can run after logout ---
sudo loginctl enable-linger sapuser || true

# --- Create Podman rootless config ---
sudo -u sapuser mkdir -p /home/sapuser/.config/containers /home/sapuser/.local/share/containers
cat <<EOC | sudo tee /home/sapuser/.config/containers/containers.conf >/dev/null
[engine]
runtime = "runc"
events_logger = "journald"
cgroup_manager = "cgroupfs"
EOC
sudo chown -R sapuser:sapuser /home/sapuser/.config /home/sapuser/.local

# --- Prepare HANA data directory ---
sudo mkdir -p /data/hxe
sudo chown -R sapuser:sapuser /data
sudo chmod -R 775 /data

# --- Set environment for sapuser ---
cat <<'EOC' | sudo tee -a /home/sapuser/.bashrc >/dev/null
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$${XDG_RUNTIME_DIR}/bus
export PATH=/usr/bin:$PATH
alias podman='podman --cgroup-manager=cgroupfs'
EOC
sudo chown sapuser:sapuser /home/sapuser/.bashrc

# --- Verify setup ---
id sapuser
getent passwd sapuser
echo "[✅ SUCCESS] sapuser is fully configured for rootless Podman."
