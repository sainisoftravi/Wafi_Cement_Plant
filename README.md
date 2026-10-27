# ESP32 Digital Twin Platform — Full Code (Hardware Revision: 4x Load Cell/Servo + Raw Gate + 16ch Relay + Sensors)

Everything needed to run the platform end-to-end on the current hardware:

- **ESP32-1**: 4 load cells (common SCK) + 4 dispensing servos — gypsum, clay,
  iron_ore, and sand — plus a raw-material gate servo on GPIO25 with open/close
  control.
- **ESP32-2**: 16-channel relay board (2x8), 13 channels wired — crusher (gangs
  3 N20 motors), conveyor_1-4, clin, clin_heater, heat_blower, preheating_tower_fan,
  preheating_tower_heater, vibration_motor, ball_mill_1, ball_mill_2 — plus 3x
  DHT11 and 1x vibration sensor (read-only, not relay-controlled).
- Both boards talk directly to your local Mosquitto broker — no cloud, no
  ThingsBoard.

## Folder structure

```
esp32/esp1-materials/   ESP32-1 firmware (.ino) - load cells + servo dispensing
esp32/esp2-relay/       ESP32-2 firmware (.ino) - 16ch relay ON/OFF
backend/                Node.js + Express + mqtt + ws
dashboard-frontend/     React + Vite + Tailwind - live tiles + Material Targets panel
widget-frontend/        Plain HTML/JS - Cupola hotspot pages (no build step)
```

## 0. Flash the ESP32 boards

Open `esp32/esp1-materials/esp1_materials.ino` and
`esp32/esp2-relay/esp2_relay.ino` in the Arduino IDE. In each file, edit:

- `WIFI_SSID` / `WIFI_PASSWORD`
- `MQTT_BROKER_HOST` — your Mosquitto machine's LAN IP
- On ESP32-2 only: `RELAY_ACTIVE_LOW` — flip to `false` if your relays energize
  on HIGH instead of LOW (test one channel first before wiring everything up)

Install the libraries listed at the top of each `.ino` file, then upload.
Wiring/pin tables are in the comment block at the top of each file.

## Prerequisites

- Node.js LTS installed
- Mosquitto already running on your local network (Architecture v4), reachable
  from the machine you run the backend on
- ESP32 boards flashed with the firmware, pointed at the same Mosquitto broker

## Run everything with one command (Windows)

From the project root, run:

```powershell
.\start.ps1
```

The script installs missing Node dependencies, then starts the backend, dashboard,
and widget server together. Open `http://localhost:5173` for the dashboard and
use `http://localhost:4173/widget.html?id=iron_ore` for a widget page. Press
`Ctrl+C` once to stop all three services.

Use `.\start.ps1 -SkipInstall` after dependencies have already been installed.

## Run with Docker Compose

The Docker Compose configuration (`docker-compose.yml`) provides a complete, self-contained environment with built-in CPU and memory resource limits:

```powershell
docker compose up --build -d
```

Services started:
- **Mosquitto** (`1883:1883`) — Lightweight containerized MQTT broker with LAN access for ESP32 boards.
- **Backend** (`4000:4000`) — Node.js REST API & WebSocket server, auto-connected to the containerized Mosquitto broker and HiveMQ Cloud bridge. Includes live code reload mounts.
- **Dashboard** (`5173:80`) — Production Nginx serving the React digital twin dashboard.
- **Widget Frontend** (`4173:4173`) — Express server serving live hotspot widget and control pages. Includes live code reload mounts.

To stop the containers, run `docker compose down`.

> [!NOTE]
> If Mosquitto was previously installed directly on the host machine via systemd, disable the host service (`sudo systemctl stop mosquitto && sudo systemctl disable mosquitto`) so the Docker Mosquitto service can bind to port `1883`. Host and ESP32 boards can reach the broker at `<host-ip>:1883`.

## 1. Backend

```bash
cd backend
npm install
cp .env.example .env       # then edit MQTT_HOST to your Mosquitto machine's LAN IP
npm run dev
```

Set `OTA_UPDATE_PASSWORD` in `backend/.env` to the password required before
triggering a firmware update from the dashboard. Keep this value private and
do not commit your `.env` file.

Verify: open `http://localhost:4000/api/items` — you should get JSON with
every item, and live values once the ESP32 boards are publishing.

## 2. Dashboard

```bash
cd dashboard-frontend
npm install
npm run dev
```

Open the printed localhost URL. Tiles should update live, and the
"Material Targets Configuration" panel lets you enter a target weight per
material and click "Apply Material Targets" to trigger dispensing.

If your backend isn't on `localhost:4000`, edit `src/config.js` first.

## 3. Widget pages (for Cupola)

The widget pages provide minimal, transparent overlays designed to embed seamlessly in 360 viewer hotspots (Cupola) without white borders or backgrounds.

No build step — serve the folder with any static server (or use Docker):

```bash
cd widget-frontend
npx serve .
```

### New Widget Styling & Customization Features (`widget.html`)

1. **Centralized Configuration**:
   Change styling globally in one single place at the top of `<script>` in `widget-frontend/widget.html`:
   ```javascript
   const DEFAULT_CONFIG = {
     color: "#ea580c",     // Default text color (e.g. Dark Orange)
     size: "32px",         // Default text font size
     fontWeight: "700",    // Font weight
     alarmColor: "#ff3b30",// Alarm color
     alarmSize: "24px",    // Alarm font size
     decimals: 2,          // Decimal places (e.g. 7.82 g)
   };
   ```

2. **Clean Capitalized Labels & Decimal Rounding**:
   - Automatically renders titles cleanly: `Iron Ore`, `Sand`, `Gypsum`, `Clay`, `Kiln Temp`, `Vibration Value`.
   - Automatically rounds floating numbers to clean values (e.g. `7.82 g` instead of `7.817529 g`).

3. **Dynamic URL Query Parameters** (Customize per-hotspot without editing code):
   - `&size=<px>` — Scale font size (e.g. `?id=sand&size=24`).
   - `&color=<hex>` — Custom color (e.g. `?id=sand&color=ffffff` or `&color=000000`).
   - `&valueOnly=true` — Shows **only** the value and unit, hiding the label name (e.g. `7.82 g`).
   - `&hideAlarm=true` — Hides the `UNDER WEIGHT ALARM` / `OVERLOAD ALARM` warning.
   - `&decimals=<n>` — Customize decimal precision (e.g. `&decimals=1` -> `7.8 g`).
   - *Example:* `widget.html?id=sand&size=26&color=facc15&valueOnly=true`

4. **No Iframe Scrollbars**:
   - `overflow: hidden` and custom scrollbar rules ensure no scrollbars appear inside embedded hotspot iframes.

---

## 4. Direct REST APIs (No Iframes Required)

If you are building your own custom application or frontend and do not want to use iframes, use these direct HTTP GET APIs:

### Live Values (JSON & Plain Text)
- `GET http://<host>:4000/api/items` — Returns a complete snapshot of all materials, sensors, and actuators in a single JSON response.
- `GET http://<host>:4000/api/item/:id` — Returns single item JSON: `{ "item_id": "sand", "value": 7.82, "unit": "g" }`.
- `GET http://<host>:4000/api/item/:id/text` — Returns raw plain text (e.g. `7.82 g` or `0 m/s²`).
- `GET http://<host>:4000/api/devices` — Device connection status (ESP1, ESP2 online/offline).

### Actuator Control (Simple GET URLs)
- Turn ON / OPEN: `GET http://<host>:4000/api/item/:id/action/on` (or `/action/open`)
- Turn OFF / CLOSE: `GET http://<host>:4000/api/item/:id/action/off` (or `/action/close`)
- Resume Auto PID: `POST http://<host>:4000/api/item/klin/resume-auto` (or `klin_heater`)

---

## 5. Configure Cupola

Paste the widget-frontend URLs into each hotspot's embed field:

Material value labels:
```
widget.html?id=gypsum
widget.html?id=clay
widget.html?id=iron_ore
widget.html?id=sand
control.html?id=lime_stone&action=open
control.html?id=lime_stone&action=close
```

Sensor value labels:
```
widget.html?id=clin_dht_temp
widget.html?id=clin_dht_humidity
widget.html?id=cooler_dht_temp
widget.html?id=cooler_dht_humidity
widget.html?id=preheating_tower_dht_temp
widget.html?id=preheating_tower_dht_humidity
widget.html?id=vibration_sensor
```

Actuator ON/OFF (two hotspots per actuator — swap `crusher` for any of:
conveyor_1, conveyor_2, conveyor_3, conveyor_4, clin, clin_heater, heat_blower,
preheating_tower_fan, preheating_tower_heater, vibration_motor, ball_mill_1, ball_mill_2):
```
control.html?id=crusher&action=on
control.html?id=crusher&action=off
```

## Notes

- No database anywhere — everything is live-only, in-memory, matching the
  Architecture doc's data policy.
- The GET-triggered `/action/on` and `/action/off` routes are convenient for a
  private LAN demo. Before exposing this publicly, add authentication or a
  confirmation step (see Architecture v5, Future Scope).
- `crusher` fires all 3 N20 motors (left, right, wheel) together — they're
  wired in parallel to one relay, so there's only ever one ON/OFF for it, not
  three separate controls.
- `control.html` supports two Cupola hotspot styles (persistent embed with
  live-highlighted buttons, or a link that fires immediately on open) — see
  Section 4 of `API_DOCUMENTATION.md` for exactly how each one behaves.
- `clin_dht_*` is near the clin/`clin_heater` section, `cooler_dht_*` is near
  the cooler section, and `preheating_tower_dht_*` is near the
  `preheating_tower_heater` — rename any of these (in both `esp2_relay.ino`
  and `backend/src/config/itemRegistry.js`) if a sensor moves.
- Channels 14-16 on the relay board are spare. `ball_mill_1`/`ball_mill_2`
  and the third DHT11 (`preheating_tower_dht`, on GPIO15) used up the last
  free GPIOs, so the board's GPIO budget is now fully used by channels 1-13 +
  the 3 sensors — wiring the remaining 3 channels later needs an I2C GPIO
  expander (e.g. PCF8574), not more direct ESP32 pins — see the note at the
  bottom of `esp2_relay.ino`.
- Calibration factor (96.322) and servo oscillation range (90-195) on ESP32-1
  were kept exactly as supplied. Recalibrate a specific pair individually in
  `materials[]` if its readings drift, rather than changing the shared constant.
- The backend accepts ESP1 material readings only in the 0-100 g range. Higher,
  negative, or non-numeric readings are rejected, and the last valid dashboard
  value is retained. Rejected readings are logged at most once every five
  seconds per material. This prevents large load-cell spikes from appearing as
  valid weights; it does not replace checking the load-cell wiring and power.
