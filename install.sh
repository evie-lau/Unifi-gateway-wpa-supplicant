#!/bin/bash

# UniFi Gateway wpa_supplicant Install Script
# Automates the setup process for ATT fiber modem bypass using wpa_supplicant
# 
# This script automates most of the manual process described in the README.md
# User interaction is still required for:
# - Certificate files (must be extracted from ATT modem beforehand)
# - Interface selection (device-specific)
# - MAC address (from ATT gateway)
# - UniFi dashboard VLAN configuration

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_INTERFACE=""
INTERFACE=""
MAC_ADDRESS=""
CERT_DIR=""
CONFIG_FILE=""
USE_ALTERNATIVE_INSTALL=false
ADD_SLEEP_DELAY=false
SLEEP_DELAY=10

# Known device interfaces
declare -A DEVICE_INTERFACES=(
    ["UXG Lite|UX"]="eth1"
    ["UXG Pro WAN1"]="eth0"
    ["UXG Pro WAN2"]="eth2"  
    ["UXG Max"]="eth4"
    ["UCG Ultra"]="eth4"
    ["UDR|UDM-Base"]="eth4"
    ["UDM Pro|SE WAN1"]="eth8"
    ["UDM Pro|SE WAN2"]="eth9"
)

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  UniFi Gateway wpa_supplicant Install Script"
    echo "=================================================="
    echo -e "${NC}"
    echo "This script automates the setup process for bypassing"
    echo "ATT fiber modems using wpa_supplicant on UniFi gateways."
    echo ""
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if we're on a UniFi gateway
    if [[ ! -f /usr/lib/version ]] || ! grep -q "UniFi" /usr/lib/version 2>/dev/null; then
        print_warning "This doesn't appear to be a UniFi gateway. Proceeding anyway..."
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_warning "No internet connectivity detected. Some features may not work."
    fi
    
    print_success "Prerequisites checked"
}

detect_device_interface() {
    print_info "Detecting device interface..."
    
    echo "Known UniFi gateway WAN interfaces:"
    echo "1. UXG Lite/UX - eth1"
    echo "2. UXG Pro WAN1 - eth0"
    echo "3. UXG Pro WAN2 - eth2"
    echo "4. UXG Max - eth4"
    echo "5. UCG Ultra - eth4"
    echo "6. UDR/UDM-Base - eth4"
    echo "7. UDM Pro/SE WAN1 - eth8"
    echo "8. UDM Pro/SE WAN2 - eth9"
    echo "9. Custom (specify manually)"
    echo ""
    
    read -p "Select your device (1-9): " choice
    
    case $choice in
        1) INTERFACE="eth1" ;;
        2) INTERFACE="eth0" ;;
        3) INTERFACE="eth2" ;;
        4|5|6) INTERFACE="eth4" ;;
        7) INTERFACE="eth8" ;;
        8) INTERFACE="eth9" ;;
        9) 
            read -p "Enter WAN interface name (e.g., eth1): " INTERFACE
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
    
    # Verify interface exists
    if [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
        print_error "Interface $INTERFACE does not exist on this system"
        echo "Available interfaces:"
        ls /sys/class/net/
        exit 1
    fi
    
    print_success "Selected interface: $INTERFACE"
}

check_certificates() {
    print_info "Checking for certificate files..."
    
    echo "This script requires the following files extracted from your ATT modem:"
    echo "- CA_*.pem (Root certificate)"
    echo "- Client_*.pem (Client certificate)"  
    echo "- PrivateKey_PKCS1_*.pem (Private key)"
    echo "- wpa_supplicant.conf (Configuration file)"
    echo ""
    echo "Please see: https://github.com/0x888e/certs for extraction instructions"
    echo ""
    
    read -p "Enter directory containing certificate files [current directory]: " CERT_DIR
    CERT_DIR=${CERT_DIR:-$(pwd)}
    
    # Check for required files
    local ca_cert=$(find "$CERT_DIR" -name "CA_*.pem" | head -1)
    local client_cert=$(find "$CERT_DIR" -name "Client_*.pem" | head -1)
    local private_key=$(find "$CERT_DIR" -name "PrivateKey_PKCS1_*.pem" | head -1)
    local config_file=$(find "$CERT_DIR" -name "wpa_supplicant.conf" | head -1)
    
    if [[ -z "$ca_cert" || -z "$client_cert" || -z "$private_key" || -z "$config_file" ]]; then
        print_error "Missing required certificate files in $CERT_DIR"
        echo "Found files:"
        ls -la "$CERT_DIR"/*.pem "$CERT_DIR"/wpa_supplicant.conf 2>/dev/null || echo "No certificate files found"
        exit 1
    fi
    
    print_success "Found all required certificate files"
    
    # Extract MAC address from config file
    if grep -q "00:" "$config_file"; then
        MAC_ADDRESS=$(grep -o '[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]' "$config_file" | head -1)
        print_info "Found MAC address in config: $MAC_ADDRESS"
    fi
}

get_mac_address() {
    if [[ -z "$MAC_ADDRESS" ]]; then
        echo "Enter the MAC address of your ATT gateway for spoofing"
        echo "This should be in the format XX:XX:XX:XX:XX:XX"
        read -p "MAC Address: " MAC_ADDRESS
    fi
    
    # Validate MAC address format
    if [[ ! "$MAC_ADDRESS" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        print_error "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX"
        exit 1
    fi
    
    print_success "MAC address: $MAC_ADDRESS"
}

install_wpa_supplicant() {
    print_info "Installing wpa_supplicant..."
    
    echo "Choose installation method:"
    echo "1. Standard apt install (recommended)"
    echo "2. Alternative method (for UDR7/UX7 and devices with driver issues)"
    read -p "Select method (1-2): " install_choice
    
    case $install_choice in
        1)
            print_info "Installing via apt..."
            apt update -y
            apt install -y wpasupplicant
            ;;
        2)
            print_info "Installing via direct .deb download..."
            USE_ALTERNATIVE_INSTALL=true
            install_wpa_alternative
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
    
    print_success "wpa_supplicant installed"
}

install_wpa_alternative() {
    mkdir -p /etc/wpa_supplicant/packages
    cd /etc/wpa_supplicant/packages
    
    print_info "Downloading wpa_supplicant packages..."
    wget -q http://ftp.us.debian.org/debian/pool/main/w/wpa/wpasupplicant_2.9.0-21+deb11u3_arm64.deb
    wget -q http://ftp.us.debian.org/debian/pool/main/p/pcsc-lite/libpcsclite1_1.9.1-1_arm64.deb
    
    print_info "Installing packages..."
    dpkg -i *.deb
}

setup_directories() {
    print_info "Creating necessary directories..."
    mkdir -p /etc/wpa_supplicant/certs
    mkdir -p /etc/wpa_supplicant/packages
    print_success "Directories created"
}

copy_certificates() {
    print_info "Copying certificate files..."
    
    # Copy certificate files
    cp "$CERT_DIR"/CA_*.pem /etc/wpa_supplicant/certs/
    cp "$CERT_DIR"/Client_*.pem /etc/wpa_supplicant/certs/
    cp "$CERT_DIR"/PrivateKey_PKCS1_*.pem /etc/wpa_supplicant/certs/
    
    # Copy and rename config file
    cp "$CERT_DIR/wpa_supplicant.conf" "/etc/wpa_supplicant/wpa_supplicant-wired-${INTERFACE}.conf"
    
    # Update paths in config file to use absolute paths
    local config_file="/etc/wpa_supplicant/wpa_supplicant-wired-${INTERFACE}.conf"
    sed -i 's|ca_cert="CA_|ca_cert="/etc/wpa_supplicant/certs/CA_|g' "$config_file"
    sed -i 's|client_cert="Client_|client_cert="/etc/wpa_supplicant/certs/Client_|g' "$config_file"
    sed -i 's|private_key="PrivateKey_PKCS1_|private_key="/etc/wpa_supplicant/certs/PrivateKey_PKCS1_|g' "$config_file"
    
    print_success "Certificate files copied and configured"
}

setup_mac_spoofing() {
    print_info "Setting up MAC address spoofing..."
    
    echo "Choose MAC spoofing method:"
    echo "1. UniFi Dashboard (recommended - set manually in Settings > Internet > WAN > MAC Address Clone)"
    echo "2. Automatic script (creates /etc/network/if-up.d/changemac)"
    read -p "Select method (1-2): " mac_choice
    
    case $mac_choice in
        1)
            print_warning "Please manually configure MAC address clone in UniFi Dashboard:"
            print_warning "Settings > Internet > WAN > Enable 'MAC Address Clone' > Enter: $MAC_ADDRESS"
            read -p "Press Enter when you have configured the MAC address in the dashboard..."
            ;;
        2)
            create_mac_spoof_script
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac
}

create_mac_spoof_script() {
    print_info "Creating MAC spoofing script..."
    
    cat > /etc/network/if-up.d/changemac << EOF
#!/bin/sh

if [ "\$IFACE" = $INTERFACE ]; then
  ip link set dev "\$IFACE" address $MAC_ADDRESS
fi
EOF
    
    chmod 755 /etc/network/if-up.d/changemac
    
    # Apply MAC address now
    ip link set dev "$INTERFACE" address "$MAC_ADDRESS"
    
    print_success "MAC spoofing configured for $INTERFACE"
}

setup_wpa_service() {
    print_info "Setting up wpa_supplicant service..."
    
    # Ask about sleep delay
    echo "Some devices need a startup delay for wpa_supplicant to work properly after reboots."
    read -p "Add 10-second startup delay? (recommended for UDM Pro) [y/N]: " add_delay
    
    if [[ "$add_delay" =~ ^[Yy] ]]; then
        ADD_SLEEP_DELAY=true
        read -p "Enter delay in seconds [10]: " delay_input
        SLEEP_DELAY=${delay_input:-10}
    fi
    
    # Start and enable the service
    systemctl start "wpa_supplicant-wired@$INTERFACE"
    systemctl enable "wpa_supplicant-wired@$INTERFACE"
    
    # Add sleep delay if requested
    if [[ "$ADD_SLEEP_DELAY" == true ]]; then
        grep -q "ExecStartPre" "/lib/systemd/system/wpa_supplicant-wired@.service" || \
        sed -i "/Type=simple/a ExecStartPre=/bin/sleep $SLEEP_DELAY" "/lib/systemd/system/wpa_supplicant-wired@.service"
        print_info "Added ${SLEEP_DELAY}s startup delay"
    fi
    
    print_success "wpa_supplicant service configured"
}

setup_firmware_survival() {
    print_info "Setting up firmware update survival..."
    
    # Download packages if not using alternative install
    if [[ "$USE_ALTERNATIVE_INSTALL" != true ]]; then
        print_info "Downloading packages for firmware update survival..."
        mkdir -p /etc/wpa_supplicant/packages
        cd /etc/wpa_supplicant/packages
        wget -q http://ftp.us.debian.org/debian/pool/main/w/wpa/wpasupplicant_2.9.0-21+deb11u3_arm64.deb
        wget -q http://ftp.us.debian.org/debian/pool/main/p/pcsc-lite/libpcsclite1_1.9.1-1_arm64.deb
    fi
    
    # Create reinstall service
    cat > /etc/systemd/system/reinstall-wpa.service << EOF
[Unit]
Description=Reinstall and start/enable wpa_supplicant
AssertPathExistsGlob=/etc/wpa_supplicant/packages/wpasupplicant*arm64.deb
AssertPathExistsGlob=/etc/wpa_supplicant/packages/libpcsclite1*arm64.deb
ConditionPathExists=!/sbin/wpa_supplicant
After=network-online.target
Requires=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sh -c 'dpkg -Ri /etc/wpa_supplicant/packages'
EOF

    # Add sleep delay persistence if configured
    if [[ "$ADD_SLEEP_DELAY" == true ]]; then
        cat >> /etc/systemd/system/reinstall-wpa.service << EOF
ExecStartPre=/bin/sh -c 'grep -q "ExecStartPre" /lib/systemd/system/wpa_supplicant-wired\\@.service || sed -i "/Type\\=simple/a ExecStartPre=/bin/sleep $SLEEP_DELAY" /lib/systemd/system/wpa_supplicant-wired\\@.service'
EOF
    fi

    cat >> /etc/systemd/system/reinstall-wpa.service << EOF
ExecStart=/bin/sh -c 'systemctl start wpa_supplicant-wired@$INTERFACE'
ExecStartPost=/bin/sh -c 'systemctl enable wpa_supplicant-wired@$INTERFACE'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    systemctl daemon-reload
    systemctl enable reinstall-wpa.service
    
    print_success "Firmware update survival configured"
}

test_configuration() {
    print_info "Testing wpa_supplicant configuration..."
    
    echo "Testing authentication (this may take 30-60 seconds)..."
    echo "You should see 'EAP authentication completed successfully' if working correctly."
    echo ""
    
    timeout 60 wpa_supplicant -i "$INTERFACE" -D wired -c "/etc/wpa_supplicant/wpa_supplicant-wired-${INTERFACE}.conf" || true
    
    echo ""
    print_info "Test completed. Check the output above for authentication success."
    
    # Check service status
    print_info "Checking service status..."
    systemctl status "wpa_supplicant-wired@$INTERFACE" --no-pager || true
}

print_next_steps() {
    echo ""
    print_success "Installation completed!"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Set VLAN ID to 0 in UniFi Dashboard:"
    echo "   Settings > Internet > Primary (WAN1) > Enable VLAN ID > Set to 0"
    echo ""
    echo "2. Connect ethernet cable from ATT ONT to your UniFi gateway WAN port ($INTERFACE)"
    echo ""
    echo "3. Monitor the service status:"
    echo "   systemctl status wpa_supplicant-wired@$INTERFACE"
    echo ""
    echo "4. If you experience connectivity issues after reboot, you may need to:"
    echo "   - Increase the startup delay"
    echo "   - Check MAC address spoofing is working"
    echo ""
    echo -e "${YELLOW}Important files created:${NC}"
    echo "- /etc/wpa_supplicant/wpa_supplicant-wired-${INTERFACE}.conf"
    echo "- /etc/wpa_supplicant/certs/ (certificate files)"
    echo "- /etc/systemd/system/reinstall-wpa.service"
    if [[ -f "/etc/network/if-up.d/changemac" ]]; then
        echo "- /etc/network/if-up.d/changemac"
    fi
    echo ""
    print_success "Setup complete! Your UniFi gateway should now bypass the ATT modem."
}

main() {
    print_banner
    
    check_root
    check_prerequisites
    detect_device_interface
    check_certificates
    get_mac_address
    
    install_wpa_supplicant
    setup_directories
    copy_certificates
    setup_mac_spoofing
    setup_wpa_service
    setup_firmware_survival
    
    test_configuration
    print_next_steps
}

# Run main function
main "$@"