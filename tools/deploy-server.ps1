# Deploy of the online server (server/, Go) to the production host:
#   1. go vet + go test (stop on a failure)
#   2. protocol version against the last release's game (stop if it differs,
#      unless -Force: the released game could no longer play online)
#   3. Linux build (amd64)
#   4. copy binary + systemd unit to the host
#   5. install (old binary kept as stunt-racer-server.prev), unit only if
#      changed, restart, check that it runs and listens
#
#   powershell -ExecutionPolicy Bypass -File tools/deploy-server.ps1 [-Force] [-SkipTests]
#
# The host runs the server as the systemd service stunt-racer, set up as in
# docs/server-install.md. The restart drops races running on it.
# Rollback: ssh -p 29876 root@gutshof-guentert.de "install -m 755 /usr/local/bin/stunt-racer-server.prev /usr/local/bin/stunt-racer-server && systemctl restart stunt-racer"

param(
    [switch]$Force,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$ServerDir = Join-Path $Root "server"
$HostName = "root@gutshof-guentert.de"
$Port = "29876"
$Binary = Join-Path $ServerDir "stunt-racer-server"
$Unit = Join-Path $ServerDir "deploy\stunt-racer.service"
$SshOpts = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=20")

function Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

# A native program's output (stdout and stderr) as lines; success is judged
# by its exit code (ssh and go write notes to stderr, which PowerShell 5
# would turn into errors with ErrorActionPreference Stop).
function Run([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = & $exe @arguments 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $old
    }
    return $lines
}

function Show($lines) { $lines | Where-Object { $_ -notmatch 'post-quantum|store now, decrypt later|openssh.com/pq.html' } | ForEach-Object { Write-Host "   $_" } }

# --- tools ---------------------------------------------------------------------------
$Go = (Get-Command go -ErrorAction SilentlyContinue).Source
if (-not $Go) { $Go = "C:\Program Files\Go\bin\go.exe" }
if (-not (Test-Path $Go)) { throw "Go not found (PATH or C:\Program Files\Go\bin)." }
foreach ($tool in @("ssh", "scp", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found." }
}

Push-Location $ServerDir
try {
    # --- 1. tests ----------------------------------------------------------------------
    $dirty = Run "git" @("status", "--porcelain", "--", "*.go", "go.mod", "deploy")
    if ($dirty) {
        Write-Host "Uncommitted server code (it is deployed too):" -ForegroundColor Yellow
        Show $dirty
    }
    if (-not $SkipTests) {
        Step "go vet + go test"
        $out = Run $Go @("vet", ".")
        if ($LASTEXITCODE -ne 0) { Show $out; throw "go vet failed - no deploy." }
        $out = Run $Go @("test", ".")
        Show $out
        if ($LASTEXITCODE -ne 0) { throw "Tests failed - no deploy." }
    }

    # --- 2. protocol version ------------------------------------------------------------
    Step "Protocol version"
    $line = Get-Content (Join-Path $ServerDir "protocol.go") | Where-Object { $_ -match '^\s*Version\s*=' } | Select-Object -First 1
    if ($line -notmatch '=\s*(\d+)') { throw "No Version in server/protocol.go" }
    $serverVersion = [int]$Matches[1]
    Run "git" @("fetch", "--tags", "-q") | Out-Null
    $tag = (Run "git" @("tag", "--sort=-v:refname") | Select-Object -First 1)
    if ($tag) {
        $codec = Run "git" @("show", "${tag}:scripts/net/net_codec.gd")
        $cline = $codec | Where-Object { $_ -match 'const VERSION' } | Select-Object -First 1
        if ($cline -notmatch ':=\s*(\d+)') { throw "No VERSION in net_codec.gd of $tag" }
        $gameVersion = [int]$Matches[1]
        Write-Host "Server: $serverVersion, game $tag`: $gameVersion"
        if ($serverVersion -ne $gameVersion) {
            $msg = "The released game ($tag, protocol $gameVersion) cannot play online with this server (protocol $serverVersion)."
            if (-not $Force) { throw "$msg Deploy anyway with -Force." }
            Write-Host "$msg Deploying anyway (-Force)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No release yet: server protocol $serverVersion"
    }

    # --- 3. build -----------------------------------------------------------------------
    Step "Linux build"
    $env:GOOS = "linux"; $env:GOARCH = "amd64"; $env:CGO_ENABLED = "0"
    try {
        $out = Run $Go @("build", "-trimpath", "-ldflags=-s -w", "-o", "stunt-racer-server", ".")
    } finally {
        Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Binary)) { Show $out; throw "Build failed." }
    Write-Host ("stunt-racer-server: {0:N1} MB" -f ((Get-Item $Binary).Length / 1MB))
} finally {
    Pop-Location
}

try {
    # --- 4. copy ------------------------------------------------------------------------
    Step "Copy to $HostName"
    $out = Run "scp" ($SshOpts + @("-P", $Port, $Binary, $Unit, "${HostName}:/tmp/"))
    if ($LASTEXITCODE -ne 0) { Show $out; throw "scp failed ($LASTEXITCODE)." }

    # --- 5. install + restart -----------------------------------------------------------
    Step "Install and restart"
    $remote = @'
set -e
cp -p /usr/local/bin/stunt-racer-server /usr/local/bin/stunt-racer-server.prev 2>/dev/null || true
install -m 755 /tmp/stunt-racer-server /usr/local/bin/stunt-racer-server
if ! cmp -s /tmp/stunt-racer.service /etc/systemd/system/stunt-racer.service; then
  cp /tmp/stunt-racer.service /etc/systemd/system/
  systemctl daemon-reload
  echo "unit updated"
fi
rm -f /tmp/stunt-racer-server /tmp/stunt-racer.service
systemctl restart stunt-racer
sleep 2
if ! systemctl is-active --quiet stunt-racer; then
  echo "SERVICE NOT RUNNING"
  journalctl -u stunt-racer -n 30 --no-pager
  exit 3
fi
echo "service: active"
ss -ulpn | grep 27015 || { echo "NOT LISTENING ON 27015"; exit 4; }
journalctl -u stunt-racer -n 3 --no-pager
'@ -replace "`r", ""
    $out = Run "ssh" ($SshOpts + @("-p", $Port, $HostName, $remote))
    Show $out
    if ($LASTEXITCODE -ne 0) {
        throw "Remote install/restart failed ($LASTEXITCODE). Rollback: ssh -p $Port $HostName `"install -m 755 /usr/local/bin/stunt-racer-server.prev /usr/local/bin/stunt-racer-server && systemctl restart stunt-racer`""
    }
} finally {
    Remove-Item $Binary -ErrorAction SilentlyContinue
}

Step "Done"
Write-Host "Server (protocol $serverVersion) deployed to $HostName and running."
