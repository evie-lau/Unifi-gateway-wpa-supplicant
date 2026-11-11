#!/bin/bash

# Test script for install.sh
# Tests basic functionality without requiring root or actual installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install.sh"

# Test that script exists and is executable
test_script_exists() {
    echo "Testing script exists and is executable..."
    if [[ ! -f "$INSTALL_SCRIPT" ]]; then
        echo "ERROR: install.sh not found"
        exit 1
    fi
    
    if [[ ! -x "$INSTALL_SCRIPT" ]]; then
        echo "ERROR: install.sh is not executable"
        exit 1
    fi
    
    echo "✓ Script exists and is executable"
}

# Test script syntax
test_syntax() {
    echo "Testing script syntax..."
    if bash -n "$INSTALL_SCRIPT"; then
        echo "✓ Script syntax is valid"
    else
        echo "ERROR: Script has syntax errors"
        exit 1
    fi
}

# Test that required functions are defined
test_functions() {
    echo "Testing required functions are defined..."
    
    local required_functions=(
        "print_banner"
        "check_root"
        "check_prerequisites" 
        "detect_device_interface"
        "check_certificates"
        "install_wpa_supplicant"
        "setup_directories"
        "copy_certificates"
        "setup_mac_spoofing"
        "setup_wpa_service"
        "setup_firmware_survival"
        "test_configuration"
        "main"
    )
    
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$INSTALL_SCRIPT"; then
            echo "ERROR: Function $func not found"
            exit 1
        fi
    done
    
    echo "✓ All required functions are defined"
}

# Test that device interfaces are properly defined
test_device_interfaces() {
    echo "Testing device interfaces are defined..."
    
    # Check that known interfaces are in the script
    local expected_interfaces=("eth0" "eth1" "eth2" "eth4" "eth8" "eth9")
    
    for interface in "${expected_interfaces[@]}"; do
        if ! grep -q "$interface" "$INSTALL_SCRIPT"; then
            echo "ERROR: Interface $interface not found in script"
            exit 1
        fi
    done
    
    echo "✓ Device interfaces are properly defined"
}

# Test error handling patterns
test_error_handling() {
    echo "Testing error handling patterns..."
    
    # Check for proper error handling
    if ! grep -q "set -e" "$INSTALL_SCRIPT"; then
        echo "WARNING: Script doesn't use 'set -e' for error handling"
    fi
    
    if ! grep -q "print_error" "$INSTALL_SCRIPT"; then
        echo "ERROR: Script doesn't define error printing function"
        exit 1
    fi
    
    echo "✓ Error handling patterns found"
}

# Test that script has proper shebang and structure
test_structure() {
    echo "Testing script structure..."
    
    # Check shebang
    if ! head -1 "$INSTALL_SCRIPT" | grep -q "#!/bin/bash"; then
        echo "ERROR: Script missing proper shebang"
        exit 1
    fi
    
    # Check for main function call
    if ! grep -q 'main "\$@"' "$INSTALL_SCRIPT"; then
        echo "ERROR: Script doesn't call main function"
        exit 1
    fi
    
    echo "✓ Script structure is correct"
}

# Run all tests
run_tests() {
    echo "Running install script tests..."
    echo "================================"
    
    test_script_exists
    test_syntax
    test_functions
    test_device_interfaces
    test_error_handling
    test_structure
    
    echo ""
    echo "✓ All tests passed!"
    echo "The install script appears to be properly structured."
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi