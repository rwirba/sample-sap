sudo dnf install -y python3.11 python3.11-pip
python3.11 -m pip install --upgrade pip
python3.11 -m venv ~/.venvs/podman
source ~/.venvs/podman/bin/activate
pip install podman-compose