# Online-Server auf Linux installieren

Der Server (`server/`, Go) braucht keine Konfiguration und rechnet keine Physik. Ein kleiner VPS reicht.
Spieler tragen Name, Autofarbe und Serveradresse im MULTIPLAYER-Menü des Spiels ein.

## 1. Server-Programm bauen (Windows-Rechner)

Architektur des Linux-Servers prüfen: `uname -m` → `x86_64` = `amd64`, `aarch64` = `arm64`.

In PowerShell im Projektordner:

```powershell
cd server
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -trimpath -ldflags="-s -w" -o stunt-racer-server .
Remove-Item Env:GOOS, Env:GOARCH
```

Bei ARM `GOARCH="arm64"` setzen. Die fertige Datei wird von Git ignoriert.

## 2. Auf den Server kopieren

```powershell
scp stunt-racer-server deploy/stunt-racer.service user@dein-server:/tmp/
```

## 3. Als Dienst einrichten (Linux-Server)

```bash
sudo install -m 755 /tmp/stunt-racer-server /usr/local/bin/
sudo cp /tmp/stunt-racer.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now stunt-racer
```

Der Dienst läuft ohne Root-Rechte, mit höchstens 64 MB RAM, und startet nach Absturz oder Neustart von selbst.

## 4. UDP-Port 27015 freigeben

```bash
sudo ufw allow 27015/udp                                                           # Ubuntu/Debian
sudo firewall-cmd --permanent --add-port=27015/udp && sudo firewall-cmd --reload   # Fedora/RHEL
```

Hat der Hoster eine eigene Firewall im Kundenmenü (Hetzner, AWS, Oracle …), dort ebenfalls **UDP** 27015 freigeben – TCP reicht nicht.

## 5. Prüfen

```bash
systemctl status stunt-racer
sudo ss -ulpn | grep 27015          # lauscht er auf dem Port?
journalctl -u stunt-racer -f        # Live-Log: hello "JOHAN" from …, Rennen, Ergebnis
```

## 6. Im Spiel verbinden

1. **MULTIPLAYER** → **EINSTELLUNGEN** → **SERVER** → Adresse eintragen, z. B. `203.0.113.5` oder `racer.example.de` (ohne Port, `host:port` geht auch).
2. Optional **NAME** und **AUTOFARBE** anpassen.
3. Oben muss „VERBUNDEN, PING … MS“ stehen.
4. Ein Spieler wählt eine **STRECKE** (eingebaut oder aus dem Streckeneditor) und dann **RENNEN ANBIETEN**. Der andere sieht das Angebot unter **OFFENE RENNEN** und wählt es aus; das Rennen startet sofort. Eine Strecke aus dem Editor bekommt der andere für dieses Rennen mitgeschickt.

## Update

Schritt 1 und 2 wiederholen, dann:

```bash
sudo install -m 755 /tmp/stunt-racer-server /usr/local/bin/ && sudo systemctl restart stunt-racer
```

Nötig nur, wenn sich Server oder Protokoll ändern. Passt die Version nicht, zeigt das Spiel „SERVER-VERSION PASST NICHT“.

## Alternativen zu Schritt 1–2

**Direkt auf dem Server bauen** (braucht Go ≥ 1.22, z. B. `sudo apt install golang-go`):

```bash
git clone https://github.com/Tachy/Stunt-Track-Racer-VR.git
cd Stunt-Track-Racer-VR/server
go build -trimpath -ldflags="-s -w" -o /tmp/stunt-racer-server .
cp deploy/stunt-racer.service /tmp/
```

Weiter mit Schritt 3. Update: `git pull`, neu bauen, installieren wie oben.

**Docker** (ersetzt Schritt 1–3):

```bash
git clone https://github.com/Tachy/Stunt-Track-Racer-VR.git
docker build -t stunt-racer-server Stunt-Track-Racer-VR/server/
docker run -d --name stunt-racer --restart=unless-stopped -p 27015:27015/udp stunt-racer-server
docker logs -f stunt-racer
```

## Fehlersuche

- Im Spiel bleibt „VERBINDE …“ stehen: Port 27015/UDP in beiden Firewalls (Server und Hoster) prüfen, Adresse prüfen, `journalctl -u stunt-racer -f` mitlaufen lassen – kommt kein `hello`, erreichen die Pakete den Server nicht.
- Letzte Log-Zeilen: `journalctl -u stunt-racer -n 50`.
- Testen mit simulierter schlechter Leitung: `stunt-racer-server -v -sim-latency 80ms -sim-loss 0.03`.
