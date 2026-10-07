# Installing the online server on Linux

The server (`server/`, Go) needs no configuration and runs no physics; a small VPS is enough.
Players enter their name, car colour and the server address in the game's MULTIPLAYER menu.

## 1. Build the server (Windows machine)

Check the Linux server's architecture: `uname -m` → `x86_64` = `amd64`, `aarch64` = `arm64`.

In PowerShell in the project folder:

```powershell
cd server
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -trimpath -ldflags="-s -w" -o stunt-racer-server .
Remove-Item Env:GOOS, Env:GOARCH
```

Use `GOARCH="arm64"` for ARM. Git ignores the built file.

## 2. Copy it to the server

```powershell
scp stunt-racer-server deploy/stunt-racer.service user@your-server:/tmp/
```

## 3. Install as a service (Linux server)

```bash
sudo install -m 755 /tmp/stunt-racer-server /usr/local/bin/
sudo cp /tmp/stunt-racer.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now stunt-racer
```

The service runs without root, with at most 64 MB RAM, and restarts after a crash or reboot.

## 4. Open UDP port 27015

```bash
sudo ufw allow 27015/udp                                                           # Ubuntu/Debian
sudo firewall-cmd --permanent --add-port=27015/udp && sudo firewall-cmd --reload   # Fedora/RHEL
```

If the hoster has its own firewall in the customer panel (Hetzner, AWS, Oracle …), open **UDP** 27015 there too – TCP is not enough.

## 5. Check

```bash
systemctl status stunt-racer
sudo ss -ulpn | grep 27015          # listening on the port?
journalctl -u stunt-racer -f        # live log: hello "NAME" from …, races, results
```

## 6. Connect from the game

1. **MULTIPLAYER** → **SERVER** → enter the address, e.g. `203.0.113.5` or `racer.example.org` (no port needed; `host:port` works too).
2. Optionally change **NAME** and **CAR COLOUR**.
3. The top line must read "CONNECTED, PING … MS".
4. Both players choose **FIND AN OPPONENT**. Whoever searches first picks the track.

## Updating

Repeat steps 1 and 2, then:

```bash
sudo install -m 755 /tmp/stunt-racer-server /usr/local/bin/ && sudo systemctl restart stunt-racer
```

Only needed when the server or the protocol changes. On a version mismatch the game shows "SERVER VERSION DIFFERS".

## Alternatives to steps 1–2

**Build on the server** (needs Go ≥ 1.22, e.g. `sudo apt install golang-go`):

```bash
git clone https://github.com/Tachy/Stunt-Track-Racer-VR.git
cd Stunt-Track-Racer-VR/server
go build -trimpath -ldflags="-s -w" -o /tmp/stunt-racer-server .
cp deploy/stunt-racer.service /tmp/
```

Continue with step 3. To update: `git pull`, rebuild, install as above.

**Docker** (replaces steps 1–3):

```bash
git clone https://github.com/Tachy/Stunt-Track-Racer-VR.git
docker build -t stunt-racer-server Stunt-Track-Racer-VR/server/
docker run -d --name stunt-racer --restart=unless-stopped -p 27015:27015/udp stunt-racer-server
docker logs -f stunt-racer
```

## Troubleshooting

- The game stays at "CONNECTING ...": check UDP port 27015 in both firewalls (server and hoster) and the address, and watch `journalctl -u stunt-racer -f` – no `hello` means the packets do not reach the server.
- Last log lines: `journalctl -u stunt-racer -n 50`.
- Test with a simulated bad line: `stunt-racer-server -v -sim-latency 80ms -sim-loss 0.03`.
