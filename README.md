# SSH Tunnel Auto Setup

Automated bash script for creating persistent SSH reverse tunnels using autossh and systemd.

## Quick Start

1. Copy configuration:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your settings

3. Run setup:
   ```bash
   ./setup-tunnel.sh
   ```

## Commands

- `./setup-tunnel.sh` - Initial setup (installs autossh, creates service)
- `./setup-tunnel.sh --status` - Check tunnel status
- `./setup-tunnel.sh --restart` - Restart tunnel service
- `./setup-tunnel.sh --stop` - Stop tunnel service
- `./setup-tunnel.sh --remove` - Remove tunnel service
- `./setup-tunnel.sh --help` - Show help

## Environment Variables

- `CLIENT_USER` - Local username
- `CLIENT_PORT` - Local port to tunnel from
- `SERVER_USER` - Remote server username
- `SERVER_IP` - Remote server IP address
- `SERVER_PORT` - Remote server port to tunnel to
- `SSH_KEY_PATH` - Path to SSH private key
- `SERVICE_NAME` - Optional service name (auto-generated if omitted)
