# Install Script Usage Guide

## Overview
The `install.sh` script automates most of the manual setup process described in the main README. It handles device detection, package installation, configuration, and service setup while providing interactive prompts for required user inputs.

## Prerequisites

### Required Before Running Script
1. **Extract certificates from your ATT modem** using the [mfg_dat_decode tool](https://github.com/0x888e/certs)
2. **Files needed on your gateway:**
   - `CA_*.pem` (Root certificate)
   - `Client_*.pem` (Client certificate)
   - `PrivateKey_PKCS1_*.pem` (Private key)
   - `wpa_supplicant.conf` (Configuration file)
   - `install.sh` (This script)

### Transfer Files to Gateway
```bash
# Copy all required files to your gateway
scp install.sh *.pem wpa_supplicant.conf <gateway_ip>:~/
```

## Running the Script

### Basic Usage
```bash
# SSH into your gateway
ssh <gateway_ip>

# Run the install script as root
sudo ./install.sh
```

### What the Script Will Do

#### 1. Device Detection
- Automatically detects your UniFi gateway type
- Presents menu of known device interfaces:
  - UXG Lite/UX → eth1
  - UXG Pro WAN1 → eth0  
  - UXG Pro WAN2 → eth2
  - UXG Max → eth4
  - UCG Ultra → eth4
  - UDR/UDM-Base → eth4
  - UDM Pro/SE WAN1 → eth8
  - UDM Pro/SE WAN2 → eth9
  - Custom interface option

#### 2. Certificate Validation
- Checks for required certificate files
- Validates file presence and formats
- Extracts MAC address from config file if present

#### 3. wpa_supplicant Installation
- **Standard method**: `apt install wpasupplicant`
- **Alternative method**: Direct .deb download (for UDR7/UX7 and devices with driver issues)

#### 4. Configuration Setup
- Creates required directories (`/etc/wpa_supplicant/certs`, `/etc/wpa_supplicant/packages`)
- Copies and configures certificate files with absolute paths
- Renames config file to interface-specific format

#### 5. MAC Address Spoofing
- **Option 1**: Manual UniFi dashboard configuration (recommended)
- **Option 2**: Automatic script creation (`/etc/network/if-up.d/changemac`)

#### 6. Service Configuration
- Starts and enables `wpa_supplicant-wired@<interface>` service
- Optional startup delay configuration (recommended for UDM Pro)

#### 7. Firmware Update Survival
- Downloads/caches required .deb packages
- Creates `reinstall-wpa.service` for automatic recovery after firmware updates

#### 8. Testing
- Tests wpa_supplicant configuration
- Displays service status
- Provides troubleshooting output

## Interactive Prompts

### Device Interface Selection
```
Select your device (1-9):
1. UXG Lite/UX - eth1
2. UXG Pro WAN1 - eth0
...
9. Custom (specify manually)
```

### Installation Method
```
Choose installation method:
1. Standard apt install (recommended)
2. Alternative method (for UDR7/UX7 and devices with driver issues)
```

### MAC Address Configuration
```
Choose MAC spoofing method:
1. UniFi Dashboard (recommended)
2. Automatic script
```

### Startup Delay
```
Add 10-second startup delay? (recommended for UDM Pro) [y/N]:
```

## Manual Steps Still Required

### 1. UniFi Dashboard VLAN Configuration
After script completion, manually configure:
- **Settings** → **Internet** → **Primary (WAN1)**
- Enable **VLAN ID**
- Set to **0**

### 2. Physical Connection
- Unplug ethernet from ATT ONT
- Connect to UniFi gateway WAN port

## File Locations

### Created by Script
```
/etc/
├── network/
│   └── if-up.d/
│       └── changemac (if automatic MAC spoofing chosen)
├── systemd/
│   └── system/
│       └── reinstall-wpa.service
└── wpa_supplicant/
    ├── wpa_supplicant-wired-<interface>.conf
    ├── certs/
    │   ├── CA_*.pem
    │   ├── Client_*.pem
    │   └── PrivateKey_PKCS1_*.pem
    └── packages/
        ├── wpasupplicant_*_arm64.deb
        └── libpcsclite1_*_arm64.deb
```

## Troubleshooting

### Common Issues

#### 1. Script Fails with Permission Error
```bash
# Ensure you're running as root
sudo ./install.sh
```

#### 2. Certificate Files Not Found
```bash
# Verify files are in the specified directory
ls -la *.pem wpa_supplicant.conf

# Check the directory path you provided to the script
```

#### 3. Interface Not Found
```bash
# Check available interfaces
ls /sys/class/net/

# Select the correct WAN interface for your device
```

#### 4. wpa_supplicant Service Fails
```bash
# Check service status
systemctl status wpa_supplicant-wired@<interface>

# Check logs
journalctl -u wpa_supplicant-wired@<interface>

# Test manually
wpa_supplicant -i <interface> -D wired -c /etc/wpa_supplicant/wpa_supplicant-wired-<interface>.conf
```

#### 5. No Internet After Reboot
- May need startup delay (run script again and add delay)
- Verify MAC address spoofing is working
- Check VLAN configuration in UniFi dashboard

### Manual Recovery

If something goes wrong, you can manually undo changes:

```bash
# Stop and disable services
systemctl stop wpa_supplicant-wired@<interface>
systemctl disable wpa_supplicant-wired@<interface>
systemctl disable reinstall-wpa.service

# Remove files
rm -rf /etc/wpa_supplicant/
rm -f /etc/systemd/system/reinstall-wpa.service
rm -f /etc/network/if-up.d/changemac

# Reload systemd
systemctl daemon-reload
```

## Testing the Installation

### Verify Service Status
```bash
systemctl status wpa_supplicant-wired@<interface>
```

### Test Authentication Manually
```bash
wpa_supplicant -i <interface> -D wired -c /etc/wpa_supplicant/wpa_supplicant-wired-<interface>.conf
```

### Expected Success Output
```
eth1: CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully
eth1: CTRL-EVENT-CONNECTED - Connection to XX:XX:XX:XX:XX:XX completed
```

## Support

For issues not covered here:
1. Check the main README troubleshooting section
2. Verify manual process works before using script
3. Test with manual wpa_supplicant command for debugging