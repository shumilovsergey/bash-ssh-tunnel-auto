#!/bin/bash

# SSH Tunnel Auto Setup Script
# This script sets up an SSH reverse tunnel service using autossh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root for system operations
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_info "Run as regular user. Sudo will be prompted when needed."
        exit 1
    fi
}

# Load environment variables
load_env() {
    if [[ ! -f ".env" ]]; then
        print_error ".env file not found!"
        print_info "Please create .env file with required variables:"
        print_info "CLIENT_USER, CLIENT_PORT, SERVER_USER, SERVER_IP, SERVER_PORT, SSH_KEY_PATH, SERVICE_NAME"
        exit 1
    fi

    source .env

    # Validate required variables (SERVICE_NAME is optional as we'll generate it)
    local required_vars=("CLIENT_USER" "CLIENT_PORT" "SERVER_USER" "SERVER_IP" "SERVER_PORT" "SSH_KEY_PATH")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            print_error "Required variable $var is not set in .env file"
            exit 1
        fi
    done

    # Generate service name if not provided
    if [[ -z "$SERVICE_NAME" ]]; then
        # Clean IP for filename (replace dots with underscores)
        local clean_ip=$(echo "$SERVER_IP" | tr '.' '_')
        SERVICE_NAME="ssh_tunnel_${CLIENT_PORT}_to_${clean_ip}_${SERVER_PORT}"
    fi

    print_info "Environment variables loaded successfully"
    print_info "Service name: $SERVICE_NAME"
}

# Check if autossh is installed, install if needed
check_autossh() {
    print_info "Checking autossh installation..."

    if command -v autossh &> /dev/null; then
        print_info "autossh is already installed"
        return 0
    fi

    print_warning "autossh not found. Installing..."

    # Detect package manager and install autossh
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y autossh
    elif command -v yum &> /dev/null; then
        sudo yum install -y autossh
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm autossh
    elif command -v brew &> /dev/null; then
        brew install autossh
    else
        print_error "No supported package manager found (apt, yum, pacman, brew)"
        exit 1
    fi

    if command -v autossh &> /dev/null; then
        print_info "autossh installed successfully"
    else
        print_error "Failed to install autossh"
        exit 1
    fi
}

# Check if port is available
check_port() {
    local port=$1
    local host=${2:-localhost}

    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    else
        # Fallback: try to bind to port
        if timeout 1 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

# Check port availability
check_ports() {
    print_info "Checking port availability..."

    # Check client port
    if ! check_port "$CLIENT_PORT"; then
        print_error "Client port $CLIENT_PORT is already in use"
        print_info "Please choose a different CLIENT_PORT in .env file"
        exit 1
    fi
    print_info "Client port $CLIENT_PORT is available"

    # Check if we can connect to server port (optional check)
    print_info "Note: Server port $SERVER_PORT will be used on the remote server"
    print_warning "Make sure port $SERVER_PORT is available on the server side"
}

# Validate SSH key
validate_ssh_key() {
    print_info "Validating SSH key..."

    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        print_error "SSH key not found at: $SSH_KEY_PATH"
        print_info "Please ensure the SSH key exists and the path is correct in .env"
        exit 1
    fi

    # Check key permissions
    local key_perms=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%OLp" "$SSH_KEY_PATH")
    if [[ "$key_perms" != "600" ]]; then
        print_warning "SSH key permissions are not secure ($key_perms). Setting to 600..."
        chmod 600 "$SSH_KEY_PATH"
    fi

    print_info "SSH key validated successfully"
}

# Test SSH connection
test_ssh_connection() {
    print_info "Testing SSH connection to $SERVER_USER@$SERVER_IP..."

    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$SERVER_USER@$SERVER_IP" "echo 'SSH connection successful'" &>/dev/null; then
        print_info "SSH connection test passed"
    else
        print_error "Failed to connect to $SERVER_USER@$SERVER_IP"
        print_info "Please check:"
        print_info "  - Server IP address and user credentials"
        print_info "  - SSH key permissions and authentication"
        print_info "  - Network connectivity"
        exit 1
    fi
}

# Create systemd service
create_service() {
    print_info "Creating systemd service: $SERVICE_NAME..."

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    # Create service file content
    local service_content="[Unit]
Description=AutoSSH Reverse Tunnel from Client to Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${CLIENT_USER}
Restart=always
RestartSec=5
ExecStart=/usr/bin/autossh -M 0 -N -q -i ${SSH_KEY_PATH} -o \"ExitOnForwardFailure=yes\" -o \"ServerAliveInterval=30\" -o \"ServerAliveCountMax=3\" -o \"StrictHostKeyChecking=no\" -R ${SERVER_PORT}:localhost:${CLIENT_PORT} ${SERVER_USER}@${SERVER_IP}
ExecStop=/usr/bin/pkill -f \"autossh.*${SERVER_USER}@${SERVER_IP}\"

[Install]
WantedBy=multi-user.target"

    # Write service file
    echo "$service_content" | sudo tee "$service_file" > /dev/null

    # Set proper permissions
    sudo chmod 644 "$service_file"

    # Reload systemd
    sudo systemctl daemon-reload

    print_info "Service file created: $service_file"
}

# Start and enable service
start_service() {
    print_info "Starting and enabling $SERVICE_NAME service..."

    # Start the service
    if sudo systemctl start "$SERVICE_NAME"; then
        print_info "Service started successfully"
    else
        print_error "Failed to start service"
        sudo systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi

    # Enable the service
    if sudo systemctl enable "$SERVICE_NAME"; then
        print_info "Service enabled for automatic startup"
    else
        print_warning "Failed to enable service for automatic startup"
    fi

    # Show status
    print_info "Service status:"
    sudo systemctl status "$SERVICE_NAME" --no-pager -l
}

# Show usage information
show_usage() {
    echo "SSH Tunnel Auto Setup Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -s, --status   Show service status"
    echo "  -r, --restart  Restart the tunnel service"
    echo "  --stop         Stop the tunnel service"
    echo "  --remove       Remove the tunnel service"
    echo ""
    echo "Configuration:"
    echo "  Edit .env file to configure tunnel parameters"
    echo ""
}

# Show service status
show_status() {
    if [[ -f ".env" ]]; then
        source .env
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            print_info "Service $SERVICE_NAME is running"
            sudo systemctl status "$SERVICE_NAME" --no-pager -l
        else
            print_warning "Service $SERVICE_NAME is not running"
            sudo systemctl status "$SERVICE_NAME" --no-pager -l
        fi
    else
        print_error ".env file not found"
        exit 1
    fi
}

# Restart service
restart_service() {
    load_env
    print_info "Restarting $SERVICE_NAME service..."
    sudo systemctl restart "$SERVICE_NAME"
    show_status
}

# Stop service
stop_service() {
    load_env
    print_info "Stopping $SERVICE_NAME service..."
    sudo systemctl stop "$SERVICE_NAME"
    print_info "Service stopped"
}

# Remove service
remove_service() {
    load_env
    print_info "Removing $SERVICE_NAME service..."

    # Stop service if running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        sudo systemctl stop "$SERVICE_NAME"
    fi

    # Disable service
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        sudo systemctl disable "$SERVICE_NAME"
    fi

    # Remove service file
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    sudo systemctl daemon-reload

    print_info "Service removed successfully"
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -s|--status)
            show_status
            exit 0
            ;;
        -r|--restart)
            restart_service
            exit 0
            ;;
        --stop)
            stop_service
            exit 0
            ;;
        --remove)
            remove_service
            exit 0
            ;;
        "")
            # Default setup process
            print_info "Starting SSH tunnel setup..."
            check_root
            load_env
            check_autossh
            check_ports
            validate_ssh_key
            test_ssh_connection
            create_service
            start_service

            print_info ""
            print_info "🎉 SSH tunnel setup completed successfully!"
            print_info "Tunnel: localhost:$CLIENT_PORT -> $SERVER_USER@$SERVER_IP:$SERVER_PORT"
            print_info ""
            print_info "Useful commands:"
            print_info "  $0 --status    # Check tunnel status"
            print_info "  $0 --restart   # Restart tunnel"
            print_info "  $0 --stop      # Stop tunnel"
            print_info "  $0 --remove    # Remove tunnel service"
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"