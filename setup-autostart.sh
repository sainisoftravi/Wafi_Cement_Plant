#!/usr/bin/env bash
# Installs systemd services so the Cement_plant stack starts automatically at boot.
#
# Usage (from anywhere):
#   sudo bash setup-autostart.sh /path/to/Cement_plant
# If no path is given, the current directory is used.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo:  sudo bash $0 /path/to/Cement_plant" >&2
  exit 1
fi

REPO_DIR="$(realpath "${1:-$PWD}")"
RUN_USER="${SUDO_USER:-$(logname)}"

for d in backend dashboard-frontend widget-frontend; do
  [[ -d "$REPO_DIR/$d" ]] || { echo "Missing folder: $REPO_DIR/$d (wrong path?)" >&2; exit 1; }
done

command -v node >/dev/null || { echo "Node.js not found. Install it first." >&2; exit 1; }
NPM_BIN="$(command -v npm)"
NODE_DIR="$(dirname "$(command -v node)")"

echo "Repo:  $REPO_DIR"
echo "User:  $RUN_USER"
echo

# --- Dependencies & builds (run as the normal user, not root) ---
echo "==> Installing backend dependencies"
sudo -u "$RUN_USER" bash -c "cd '$REPO_DIR/backend' && npm install"
if [[ ! -f "$REPO_DIR/backend/.env" && -f "$REPO_DIR/backend/.env.example" ]]; then
  sudo -u "$RUN_USER" cp "$REPO_DIR/backend/.env.example" "$REPO_DIR/backend/.env"
  echo "    Created backend/.env - edit MQTT_HOST in it if the broker is not on this machine."
fi

echo "==> Installing dashboard dependencies and building"
sudo -u "$RUN_USER" bash -c "cd '$REPO_DIR/dashboard-frontend' && npm install && npm run build"

echo "==> Installing 'serve' globally for the widget pages"
"$NPM_BIN" install -g serve
SERVE_BIN="$(command -v serve)"

# --- Mosquitto ---
if command -v mosquitto >/dev/null; then
  systemctl enable --now mosquitto
else
  echo "WARNING: mosquitto not installed locally. Skipping (fine if your broker is on another machine)."
fi

# --- systemd unit files ---
echo "==> Writing systemd services"

cat > /etc/systemd/system/cement-backend.service <<EOF
[Unit]
Description=Cement Plant backend (Node + MQTT + WebSocket)
After=network-online.target mosquitto.service
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$REPO_DIR/backend
Environment=PATH=$NODE_DIR:/usr/local/bin:/usr/bin:/bin
ExecStart=$NPM_BIN run dev
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/cement-dashboard.service <<EOF
[Unit]
Description=Cement Plant dashboard (Vite preview of production build)
After=network-online.target cement-backend.service
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$REPO_DIR/dashboard-frontend
Environment=PATH=$NODE_DIR:/usr/local/bin:/usr/bin:/bin
ExecStart=$NPM_BIN exec -- vite preview --host 0.0.0.0 --port 5173 --strictPort
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/cement-widget.service <<EOF
[Unit]
Description=Cement Plant widget pages (static server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$REPO_DIR/widget-frontend
Environment=PATH=$NODE_DIR:/usr/local/bin:/usr/bin:/bin
ExecStart=$SERVE_BIN -l 4173 .
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cement-backend.service cement-dashboard.service cement-widget.service

echo
echo "Done. Status:"
systemctl --no-pager --lines=0 status cement-backend cement-dashboard cement-widget || true
echo
echo "Backend:   http://localhost:4000/api/items"
echo "Dashboard: http://localhost:5173"
echo "Widgets:   http://localhost:4173/widget.html?id=iron_ore"
echo
echo "Logs:  journalctl -u cement-backend -f"