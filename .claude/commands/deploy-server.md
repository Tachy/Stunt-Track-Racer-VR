---
description: Build the online server, deploy it to gutshof-guentert.de and restart it there
---

Build the Go online server (`server/`), copy it to the production host and
restart the service there. Reply in German. Do the steps in order and stop
on any error (show the error, do not work around it).

Host: `root@gutshof-guentert.de`, SSH port **29876** (`ssh -p 29876`,
`scp -P 29876`). There the server runs as the systemd service `stunt-racer`
(`/etc/systemd/system/stunt-racer.service`, binary
`/usr/local/bin/stunt-racer-server`, UDP port 27015, x86_64) - set up as in
`docs/server-install.md`.

## 1. Check and build (local)

- `git status`: report uncommitted changes in `server/` (they would be
  deployed too) - do not stop for them.
- In `server/` (Go is at `C:\Program Files\Go\bin`; in Bash first
  `export PATH="/c/Program Files/Go/bin:$PATH"`):
  - `go vet .` and `go test .` - stop if they fail.
  - Build for Linux:
    `GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o stunt-racer-server .`
    (the file is git-ignored).
- Protocol version: compare `Version` in `server/protocol.go` with `VERSION`
  in `scripts/net/net_codec.gd` of the last release:
  `git fetch --tags -q`, then the newest tag `git tag --sort=-v:refname | head -1`,
  then `git show <tag>:scripts/net/net_codec.gd | grep "const VERSION"`.
  If the server's version differs, the released game can no longer play
  online after this deploy (the server turns it away): say so and ask
  (AskUserQuestion) whether to deploy anyway. Without a yes: stop.

## 2. Copy

`scp -P 29876 server/stunt-racer-server server/deploy/stunt-racer.service root@gutshof-guentert.de:/tmp/`

## 3. Install and restart (remote, one ssh call)

```bash
ssh -p 29876 root@gutshof-guentert.de '
set -e
cp -p /usr/local/bin/stunt-racer-server /usr/local/bin/stunt-racer-server.prev 2>/dev/null || true
install -m 755 /tmp/stunt-racer-server /usr/local/bin/stunt-racer-server
if ! cmp -s /tmp/stunt-racer.service /etc/systemd/system/stunt-racer.service; then
  cp /tmp/stunt-racer.service /etc/systemd/system/ && systemctl daemon-reload && echo "unit updated"
fi
rm -f /tmp/stunt-racer-server /tmp/stunt-racer.service
systemctl restart stunt-racer
sleep 2
systemctl is-active stunt-racer
ss -ulpn | grep 27015
journalctl -u stunt-racer -n 5 --no-pager
'
```

The restart drops races that are running on the server.

## 4. Report

- Build (size), tests, whether the unit changed, `is-active`, the port line
  and the last journal lines.
- If the service is not active: show `journalctl -u stunt-racer -n 30 --no-pager`
  and offer the rollback (do not run it unasked):
  `ssh -p 29876 root@gutshof-guentert.de 'install -m 755 /usr/local/bin/stunt-racer-server.prev /usr/local/bin/stunt-racer-server && systemctl restart stunt-racer'`
- Remove the local `server/stunt-racer-server`.
