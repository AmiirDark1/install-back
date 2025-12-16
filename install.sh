#!/bin/bash

# Backhaul Manager Script (Install/Uninstall)
# Usage: sudo bash backhaul_manager.sh

set -e

echo "========================================"
echo "      Backhaul Manager Script"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Main Menu
echo -e "${CYAN}Select an option:${NC}"
echo "1) Install Backhaul"
echo "2) Uninstall Backhaul"
echo "3) Reinstall Backhaul"
echo "4) Check Status"
echo "5) Exit"
read -p "Enter your choice (1-5): " MAIN_CHOICE

case $MAIN_CHOICE in
    1)
        ACTION="install"
        ;;
    2)
        ACTION="uninstall"
        ;;
    3)
        ACTION="reinstall"
        ;;
    4)
        ACTION="status"
        ;;
    5)
        echo -e "${GREEN}Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

# Function to uninstall
uninstall_backhaul() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "         Uninstalling Backhaul"
    echo "========================================${NC}"
    
    if [ ! -f "/etc/systemd/system/backhaul.service" ]; then
        echo -e "${YELLOW}Backhaul is not installed on this system.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Stopping Backhaul service...${NC}"
    systemctl stop backhaul.service 2>/dev/null || true
    
    echo -e "${GREEN}Disabling Backhaul service...${NC}"
    systemctl disable backhaul.service 2>/dev/null || true
    
    echo -e "${GREEN}Removing service file...${NC}"
    rm -f /etc/systemd/system/backhaul.service
    
    echo -e "${GREEN}Removing Backhaul directory...${NC}"
    rm -rf /opt/backhaul
    
    echo -e "${GREEN}Reloading systemd daemon...${NC}"
    systemctl daemon-reload
    
    echo ""
    echo -e "${GREEN}========================================"
    echo "  Backhaul Uninstalled Successfully!"
    echo "========================================${NC}"
}

# Function to install
install_backhaul() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "         Installing Backhaul"
    echo "========================================${NC}"
    
    # Check if already installed
    if [ -f "/etc/systemd/system/backhaul.service" ]; then
        echo -e "${YELLOW}Backhaul is already installed!${NC}"
        read -p "Do you want to reinstall? (yes/no): " REINSTALL_CONFIRM
        if [ "$REINSTALL_CONFIRM" != "yes" ]; then
            echo -e "${RED}Installation cancelled.${NC}"
            return 1
        fi
        uninstall_backhaul
        echo ""
    fi
    
    # Ask for installation type
    echo -e "${BLUE}Select installation type:${NC}"
    echo "1) Server"
    echo "2) Client"
    read -p "Enter your choice (1 or 2): " INSTALL_TYPE
    
    case $INSTALL_TYPE in
        1)
            MODE="server"
            ;;
        2)
            MODE="client"
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Installing Backhaul in ${MODE^^} mode...${NC}"
    echo ""
    
    # Common settings
    echo -e "${YELLOW}=== Common Settings ===${NC}"
    echo -e "${YELLOW}Enter the token (default: mehdi):${NC}"
    read -p "Token: " TOKEN
    TOKEN=${TOKEN:-mehdi}
    
    if [ "$MODE" = "server" ]; then
        # Server Configuration
        echo ""
        echo -e "${YELLOW}=== Server Configuration ===${NC}"
        
        echo -e "${YELLOW}Enter the bind port (default: 1000):${NC}"
        read -p "Bind Port: " BIND_PORT
        BIND_PORT=${BIND_PORT:-1000}
        
while true; do
    echo -e "${YELLOW}Enter ports to forward (format: LOCAL:REMOTE, comma-separated)${NC}"
    echo -e "${BLUE}Examples: 443:443,2083:2083,8084:8084 or just 443,2083,8084${NC}"
    read -p "Ports: " PORTS_INPUT

    # اگر خالی بود، پیام خطا بده
    if [ -z "$PORTS_INPUT" ]; then
        echo -e "${RED}You must enter at least one port!${NC}"
        continue
    fi

    # بررسی اینکه فقط اعداد و ":" و "," دارند
    if [[ ! "$PORTS_INPUT" =~ ^[0-9,:]+$ ]]; then
        echo -e "${RED}Invalid format! Only numbers, commas, and colons are allowed.${NC}"
        continue
    fi

    # اگر همه چیز درست بود، حلقه را بشکن
    break
done

        
        # Convert ports to TOML format
        PORTS_ARRAY=""
        IFS=',' read -ra PORTS <<< "$PORTS_INPUT"
        for port in "${PORTS[@]}"; do
            port=$(echo $port | xargs)  # trim whitespace
            if [[ $port == *":"* ]]; then
                PORTS_ARRAY="${PORTS_ARRAY} \"${port}\",\n"
            else
                PORTS_ARRAY="${PORTS_ARRAY} \"${port}=${port}\",\n"
            fi
        done
        PORTS_ARRAY=$(echo -e "$PORTS_ARRAY" | sed '$ s/,$//')  # remove last comma
        
    else
        # Client Configuration
        echo ""
        echo -e "${YELLOW}=== Client Configuration ===${NC}"
        
        echo -e "${YELLOW}Enter remote server address (IP or Domain):${NC}"
        read -p "Remote Address: " REMOTE_ADDR
        
        if [ -z "$REMOTE_ADDR" ]; then
            echo -e "${RED}Remote address is required for client mode!${NC}"
            exit 1
        fi
        
        echo -e "${YELLOW}Enter the remote port (default: 1000):${NC}"
        read -p "Remote Port: " REMOTE_PORT
        REMOTE_PORT=${REMOTE_PORT:-1000}
    fi
    
    # Download and extract Backhaul
    echo ""
    echo -e "${GREEN}Creating Backhaul directory...${NC}"
    mkdir -p /opt/backhaul
    cd /opt/backhaul
    
    echo -e "${GREEN}Downloading Backhaul...${NC}"
    
    # Remove old file if exists
    rm -f backhaul_linux_amd64.tar.gz
    
    # Download with retry
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if wget --tries=3 --timeout=30 --show-progress https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz; then
            echo -e "${GREEN}Download completed successfully!${NC}"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo -e "${YELLOW}Download failed. Retrying... ($RETRY_COUNT/$MAX_RETRIES)${NC}"
                rm -f backhaul_linux_amd64.tar.gz
                sleep 2
            else
                echo -e "${RED}Download failed after $MAX_RETRIES attempts!${NC}"
                echo -e "${RED}Please check your internet connection and try again.${NC}"
                exit 1
            fi
        fi
    done
    
    # Verify downloaded file
    if [ ! -f "backhaul_linux_amd64.tar.gz" ] || [ ! -s "backhaul_linux_amd64.tar.gz" ]; then
        echo -e "${RED}Downloaded file is missing or empty!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Extracting files...${NC}"
    if ! tar -xzf backhaul_linux_amd64.tar.gz; then
        echo -e "${RED}Failed to extract archive! File might be corrupted.${NC}"
        echo -e "${YELLOW}Cleaning up and please try again...${NC}"
        rm -f backhaul_linux_amd64.tar.gz
        exit 1
    fi
    
    chmod +x backhaul
    rm -f backhaul_linux_amd64.tar.gz
    
    echo -e "${GREEN}Backhaul binary extracted successfully!${NC}"
    
    # Create configuration file
    echo -e "${GREEN}Creating configuration file...${NC}"
    
    if [ "$MODE" = "server" ]; then
        cat > /opt/backhaul/conf.toml << EOF
[server]
bind_addr = "0.0.0.0:${BIND_PORT}"
transport = "tcp"
accept_udp = false
token = "${TOKEN}"
keepalive_period = 10
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = false
web_port = 2525
sniffer_log = "/opt/backhaul/backhaul.json"
log_level = "info"
ports = [
$(echo -e "$PORTS_ARRAY")
]
EOF
    else
        cat > /opt/backhaul/conf.toml << EOF
[client]
remote_addr = "${REMOTE_ADDR}:${REMOTE_PORT}"
transport = "tcp"
token = "${TOKEN}"
connection_pool = 128
aggressive_pool = false
keepalive_period = 10
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = false
web_port = 2525
sniffer_log = "/opt/backhaul/backhaul.json"
log_level = "info"
EOF
    fi
    
    # Create systemd service
    echo -e "${GREEN}Creating systemd service...${NC}"
    cat > /etc/systemd/system/backhaul.service << EOF
[Unit]
Description=Backhaul Reverse Tunnel Service (${MODE^^})
After=network.target

[Service]
Type=simple
ExecStart=/opt/backhaul/backhaul -c /opt/backhaul/conf.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    echo -e "${GREEN}Enabling and starting Backhaul service...${NC}"
    systemctl daemon-reload
    systemctl enable backhaul.service
    systemctl start backhaul.service
    
    # Wait a moment for service to start
    sleep 2
    
    # Show status
    echo ""
    echo -e "${GREEN}========================================"
    echo "  Installation Completed Successfully!"
    echo "========================================${NC}"
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo -e "  Mode: ${GREEN}${MODE^^}${NC}"
    echo -e "  Token: ${GREEN}${TOKEN}${NC}"
    
    if [ "$MODE" = "server" ]; then
        echo -e "  Bind Port: ${GREEN}${BIND_PORT}${NC}"
        echo -e "  Forwarded Ports: ${GREEN}${PORTS_INPUT}${NC}"
    else
        echo -e "  Remote: ${GREEN}${REMOTE_ADDR}:${REMOTE_PORT}${NC}"
    fi
    
    echo ""
    systemctl status backhaul.service --no-pager
    
    echo ""
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  Check status:  ${GREEN}systemctl status backhaul${NC}"
    echo "  Restart:       ${GREEN}systemctl restart backhaul${NC}"
    echo "  Stop:          ${GREEN}systemctl stop backhaul${NC}"
    echo "  View logs:     ${GREEN}journalctl -u backhaul -f${NC}"
    echo "  Edit config:   ${GREEN}nano /opt/backhaul/conf.toml${NC}"
    echo ""
    echo -e "${BLUE}Installation directory: /opt/backhaul${NC}"
    echo -e "${BLUE}Config file location: /opt/backhaul/conf.toml${NC}"
    echo -e "${BLUE}Service file location: /etc/systemd/system/backhaul.service${NC}"
}

# Function to check status
check_status() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "         Backhaul Status"
    echo "========================================${NC}"
    
    if [ ! -f "/etc/systemd/system/backhaul.service" ]; then
        echo -e "${RED}Backhaul is not installed on this system.${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Service Status:${NC}"
    systemctl status backhaul.service --no-pager
    
    echo ""
    echo -e "${CYAN}Configuration File:${NC}"
    if [ -f "/opt/backhaul/conf.toml" ]; then
        cat /opt/backhaul/conf.toml
    else
        echo -e "${RED}Configuration file not found!${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Recent Logs:${NC}"
    journalctl -u backhaul.service -n 20 --no-pager
}

# Execute based on action
case $ACTION in
    install)
        install_backhaul
        ;;
    uninstall)
        echo ""
        echo -e "${YELLOW}This will completely remove Backhaul from your system.${NC}"
        read -p "Are you sure you want to continue? (yes/no): " CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            echo -e "${RED}Uninstallation cancelled.${NC}"
            exit 0
        fi
        uninstall_backhaul
        ;;
    reinstall)
        echo ""
        echo -e "${YELLOW}This will reinstall Backhaul (remove and install again).${NC}"
        read -p "Are you sure you want to continue? (yes/no): " CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            echo -e "${RED}Reinstallation cancelled.${NC}"
            exit 0
        fi
        uninstall_backhaul
        echo ""
        echo -e "${CYAN}Starting installation...${NC}"
        sleep 1
        install_backhaul
        ;;
    status)
        check_status
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
