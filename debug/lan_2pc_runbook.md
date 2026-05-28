# 2-PC LAN Validation Runbook (Windows)

Use this checklist when host and client are on different PCs on the same LAN.

## 1) Launch host and client

- Host PC: start game, host lobby on default UDP port `1234`.
- Client PC: join using host LAN IP (preferred) or room code.
- If using command-line entry points in custom builds, pass host/client args that map to `host_game` and `join_game`.

## 2) Get host local IPv4 (host PC)

Run in PowerShell or CMD:

```powershell
ipconfig
```

Use the active adapter IPv4 (usually `192.168.x.x` or `10.x.x.x`), not `127.0.0.1`.

## 3) Firewall checks (Windows Defender Firewall)

- Ensure inbound/outbound UDP `1234` is allowed for the game executable.
- Verify profile scope: both **Private** and **Public** as needed for your network profile.
- If unsure, create explicit inbound/outbound UDP rules for port `1234`.

## 4) Differential test (temporary firewall-off)

- Temporarily disable firewall on host only for a short test window.
- Retry client join.
- If it works only with firewall off, re-enable firewall and fix allowlist rules.

## 5) Basic reachability checks

From client PC:

```powershell
ping <HOST_LAN_IP>
```

- If ping fails, validate same subnet and router/AP settings.
- Check AP/client isolation (sometimes called Wireless Isolation) and disable it.

## 6) Expected log signatures

- Successful host startup:
  - `Server bind_ip forced to 0.0.0.0`
  - `Server started on UDP 1234 (all interfaces).`
  - `Host LAN IPv4 candidate: ...`
- Successful join:
  - `Peer connected -> id=...`
- Typical failures:
  - `profile=timeout-or-blocked` (likely firewall/routing/isolation)
  - `profile=refused-or-unreachable-fast-fail` (wrong IP/port or no listener)
  - `profile=loopback-mismatch` (`127.0.0.1` used from second PC)

## 7) Quick preflight helper

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\debug\lan_preflight.ps1 -Port 1234
```

Share the printed IPv4 and port info with the client player before testing.
