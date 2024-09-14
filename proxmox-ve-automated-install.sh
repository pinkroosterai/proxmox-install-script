#!/bin/bash

# Ensure the script is run with root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Function to check command success
check_command() {
    if [[ $1 -ne 0 ]]; then
        echo "Error: $2 failed."
        exit 1
    fi
}

# Welcome message
echo "Welcome to the Proxmox Install Script for dedicated servers..."
sleep 2

# Downloading Proxmox VE
echo "Downloading Proxmox VE..."

# Retrieve the latest Proxmox VE ISO using HTTP
ISO_VERSION=$(curl -s 'http://download.proxmox.com/iso/' | grep -oP 'proxmox-ve_\d+\.\d+-\d+\.iso' | sort -V | tail -n1)
ISO_URL="http://download.proxmox.com/iso/$ISO_VERSION"

if [[ -z "$ISO_VERSION" ]]; then
    echo "Failed to retrieve the Proxmox VE ISO version."
    exit 1
fi

echo "Latest Proxmox VE ISO Version: $ISO_VERSION"
echo "ISO URL: $ISO_URL"
echo "Downloading the Proxmox VE ISO. This may take a while..."
curl -o /tmp/proxmox-ve.iso $ISO_URL
check_command $? "Downloading Proxmox VE ISO"

# Acquire Network Configuration
echo "Acquiring Network Configuration..."

# Get the network interface name
INTERFACE_NAME=$(ip route | grep default | awk '{print $5}')

if [[ -z "$INTERFACE_NAME" ]]; then
    echo "Failed to detect the network interface."
    exit 1
fi

IP_CIDR=$(ip addr show $INTERFACE_NAME | grep "inet\b" | awk '{print $2}')
GATEWAY=$(ip route | grep default | awk '{print $3}')
IP_ADDRESS=$(echo "$IP_CIDR" | cut -d'/' -f1)
CIDR=$(echo "$IP_CIDR" | cut -d'/' -f2)

echo "Interface Name: $INTERFACE_NAME"
echo "IP Address: $IP_ADDRESS"
echo "CIDR: $CIDR"
echo "Gateway: $GATEWAY"

# Confirm network settings
while true; do
    read -p "Proceed with these network settings? (y/n): " proceed
    case $proceed in
        [Yy]* ) break;;
        [Nn]* ) echo "Aborted."; exit 1;;
        * ) echo "Please answer y or n.";;
    esac
done

# Ask for boot mode
while true; do
    echo "Do you want to install Proxmox in UEFI mode? (recommended for most systems)"
    read -p "Enter 'y' for UEFI mode or 'n' for Legacy mode: " uefi_choice
    case $uefi_choice in
        [Yy]* ) BOOT_MODE="UEFI"; break;;
        [Nn]* ) BOOT_MODE="Legacy"; break;;
        * ) echo "Please answer y or n.";;
    esac
done

echo "Selected boot mode: $BOOT_MODE"

# Get the list of disks
DISK_LIST=($(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk" {print $1}'))

if [[ ${#DISK_LIST[@]} -eq 0 ]]; then
    echo "No disks found."
    exit 1
fi

echo "Available disks:"
for i in "${!DISK_LIST[@]}"; do
    DISK_NAME=${DISK_LIST[$i]}
    DISK_SIZE=$(lsblk -dn -o SIZE /dev/$DISK_NAME)
    echo "$((i+1))) /dev/$DISK_NAME - $DISK_SIZE"
done

# Validate primary disk selection
while true; do
    read -p "Enter the number corresponding to the primary disk: " primary_choice
    if [[ "$primary_choice" =~ ^[0-9]+$ && $primary_choice -ge 1 && $primary_choice -le ${#DISK_LIST[@]} ]]; then
        PRIMARY_DISK=${DISK_LIST[$((primary_choice-1))]}
        break
    else
        echo "Invalid input. Please enter a valid disk number."
    fi
done

# Validate secondary disk selection
while true; do
    read -p "Enter the number corresponding to the secondary disk (or press Enter to skip): " secondary_choice
    if [[ -z "$secondary_choice" ]]; then
        SECONDARY_DISK=""
        break
    elif [[ "$secondary_choice" =~ ^[0-9]+$ && $secondary_choice -ge 1 && $secondary_choice -le ${#DISK_LIST[@]} ]]; then
        SECONDARY_DISK=${DISK_LIST[$((secondary_choice-1))]}
        break
    else
        echo "Invalid input. Please enter a valid disk number."
    fi
done

echo "WARNING: The selected disks will be completely erased during the installation."
echo "Primary Disk: /dev/$PRIMARY_DISK"
if [[ -n "$SECONDARY_DISK" ]]; then
    echo "Secondary Disk: /dev/$SECONDARY_DISK"
else
    echo "No Secondary Disk selected."
fi

# Confirm disk selection
while true; do
    read -p "Are you sure you want to proceed with these disks? (y/n): " confirm
    case $confirm in
        [Yy]* ) break;;
        [Nn]* ) echo "Operation aborted."; exit 1;;
        * ) echo "Please answer y or n.";;
    esac
done

# Check for required packages
echo "Checking for required packages..."
REQUIRED_PACKAGES=(qemu-kvm ovmf netcat sshpass)
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$pkg"; then
        echo "Installing $pkg..."
        apt-get update
        apt-get install -y $pkg
        check_command $? "Installing $pkg"
    else
        echo "$pkg is already installed."
    fi
done

# Set VNC password with validation
while true; do
    echo "Please enter VNC password (maximum 8 characters):"
    read -s VNC_PASSWORD1

    if [[ ${#VNC_PASSWORD1} -gt 8 ]]; then
        echo "Password is too long. It must be 8 characters or less. Please try again."
        continue
    fi

    echo "Please confirm VNC password:"
    read -s VNC_PASSWORD2

    if [[ "$VNC_PASSWORD1" == "$VNC_PASSWORD2" ]]; then
        VNC_PASSWORD="$VNC_PASSWORD1"
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

# Start QEMU for Proxmox installation
if [[ $BOOT_MODE == "UEFI" ]]; then
    echo "Starting QEMU in UEFI mode with CDROM..."

    # Prepare disk options
    DISK_OPTIONS="-drive file=/dev/$PRIMARY_DISK,format=raw,media=disk,if=virtio"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -drive file=/dev/$SECONDARY_DISK,format=raw,media=disk,if=virtio"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,readonly=on \
    -drive file=/usr/share/OVMF/OVMF_VARS.fd,if=pflash,format=raw \
    -cdrom /tmp/proxmox-ve.iso -boot d \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait
else
    echo "Starting QEMU in Legacy mode with CDROM..."

    # Prepare disk options
    DISK_OPTIONS="-hda /dev/$PRIMARY_DISK"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -hdb /dev/$SECONDARY_DISK"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -cdrom /tmp/proxmox-ve.iso -boot d \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait
fi
check_command $? "Starting QEMU for Proxmox installation"

# Wait for QEMU monitor to be available
echo "Waiting for QEMU monitor to be available..."
for i in {1..10}; do
    if nc -z 127.0.0.1 4444; then
        echo "QEMU monitor is available."
        break
    else
        echo "QEMU monitor not available yet. Retrying in 3 seconds..."
        sleep 3
    fi
done

if ! nc -z 127.0.0.1 4444; then
    echo "Failed to connect to QEMU monitor."
    exit 1
fi

# Set VNC password
echo "Setting VNC password..."
echo "change vnc password $VNC_PASSWORD" | nc -q 1 127.0.0.1 4444

echo ""
echo "========================================================================="
echo "VNC server is running on port 5900 (display :0)"
echo "You can now connect via VNC to proceed with the Proxmox installation."
echo ""
echo "Please follow these steps to install Proxmox VE via the GUI:"
echo ""
echo "1. Connect your VNC Viewer (e.g., RealVNC) to $IP_ADDRESS:5900"
echo "   - Use the VNC password you set earlier."
echo ""
echo "2. In the Proxmox VE installer, select 'Install Proxmox VE (Graphical)'."
echo "   - You may see a message saying 'No support for hardware-accelerated KVM virtualization detected'. This is safe to ignore."
echo "   - Click 'OK' to continue."
echo ""
echo "3. Agree to the license terms."
echo ""
echo "4. Choose your disk configuration:"
echo "   - For example, you can select ZFS (RAID1), but choose based on your needs."
echo ""
echo "5. Set your Country, Time zone, and Keyboard Layout."
echo ""
echo "6. Enter a root password and email address."
echo "   - We recommend using a simple password for now; some symbols may break subsequent commands."
echo ""
echo "7. Leave the network settings as default."
echo ""
echo "8. Uncheck 'Automatically reboot after successful installation' and click 'Install'."
echo ""
echo "9. Once the installation is complete, do not press 'Reboot'. Instead, return to this terminal."
echo "========================================================================="
echo ""

# Confirmation prompts
read -p "Have you completed the Proxmox VE installation and are ready to continue? (y/n): " proceed
if [[ $proceed != "y" ]]; then
    echo "Please complete the installation before proceeding."
    exit 1
fi

read -p "Are you absolutely sure you want to continue? This action is irreversible. (y/n): " confirm
if [[ $confirm != "y" ]]; then
    echo "Operation aborted."
    exit 1
fi

echo "Continuing with the next steps..."

# Stop QEMU
echo "Closing the initial QEMU session..."
echo "Executing: printf 'quit\\n' | nc 127.0.0.1 4444"
printf "quit\n" | nc 127.0.0.1 4444

# Confirm QEMU has stopped
echo "Waiting for QEMU to stop..."
sleep 5

# Start QEMU to boot from internal drive
echo "Starting QEMU to boot from the internal drive..."

if [[ $BOOT_MODE == "UEFI" ]]; then
    echo "Starting QEMU in UEFI mode without CDROM..."

    # Prepare disk options
    DISK_OPTIONS="-drive file=/dev/$PRIMARY_DISK,format=raw,media=disk,if=virtio"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -drive file=/dev/$SECONDARY_DISK,format=raw,media=disk,if=virtio"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,readonly=on \
    -drive file=/usr/share/OVMF/OVMF_VARS.fd,if=pflash,format=raw \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait \
    -net user,hostfwd=tcp::2222-:22 -net nic
else
    echo "Starting QEMU in Legacy mode without CDROM..."

    # Prepare disk options
    DISK_OPTIONS="-hda /dev/$PRIMARY_DISK"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -hdb /dev/$SECONDARY_DISK"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait \
    -net user,hostfwd=tcp::2222-:22 -net nic
fi
check_command $? "Starting QEMU to boot from internal drive"

# Set VNC password again
echo "Setting VNC password again..."

# Wait for QEMU monitor to be available
echo "Waiting for QEMU monitor to be available..."
for i in {1..10}; do
    if nc -z 127.0.0.1 4444; then
        echo "QEMU monitor is available."
        break
    else
        echo "QEMU monitor not available yet. Retrying in 3 seconds..."
        sleep 3
    fi
done

if ! nc -z 127.0.0.1 4444; then
    echo "Failed to connect to QEMU monitor."
    exit 1
fi

# Set VNC password
echo "Setting VNC password..."
echo "change vnc password $VNC_PASSWORD" | nc -q 1 127.0.0.1 4444

echo ""
echo "========================================================================="
echo "QEMU is running, and you can connect back via VNC to $IP_ADDRESS:5900."
echo "Please wait for the Proxmox VE system to boot."
echo "========================================================================="
echo ""

# Wait for the VM to boot up
echo "Waiting for the VM to boot up..."
sleep 60  # Adjust the time as needed based on your system

# Prompt for the root password set during Proxmox installation
echo "Please enter the root password you set during the Proxmox installation:"
read -s ROOT_PASSWORD
echo "Please confirm the root password:"
read -s ROOT_PASSWORD_CONFIRM

if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
    echo "Passwords do not match. Exiting."
    exit 1
fi

# Verify SSH connectivity to the VM
echo "Verifying SSH connectivity to the VM..."
for i in {1..10}; do
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'SSH connection successful'" && break
    echo "SSH not available yet. Retrying in 10 seconds..."
    sleep 10
done

if ! sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'SSH connection successful'"; then
    echo "Failed to establish SSH connection to the VM."
    exit 1
fi

# Create network configuration file
echo "Creating network configuration file..."

# Use a standard interface name inside the VM (e.g., ens18)
VM_INTERFACE_NAME="ens18"

cat > /tmp/proxmox_network_config << EOF
auto lo
iface lo inet loopback

iface $VM_INTERFACE_NAME inet manual

auto vmbr0
iface vmbr0 inet static
    address $IP_ADDRESS/$CIDR
    gateway $GATEWAY
    bridge_ports $VM_INTERFACE_NAME
    bridge_stp off
    bridge_fd 0
EOF

echo "Network configuration file created at /tmp/proxmox_network_config"
echo ""
echo "Contents:"
cat /tmp/proxmox_network_config
echo ""

read -p "Proceed to transfer the network configuration to Proxmox VE system? (y/n): " proceed
if [[ $proceed != "y" ]]; then
    echo "Operation aborted."
    exit 1
fi

# Transfer the network configuration file to Proxmox VE system
echo "Transferring network configuration to Proxmox VE system..."

sshpass -p "$ROOT_PASSWORD" scp -o StrictHostKeyChecking=no -P 2222 /tmp/proxmox_network_config root@localhost:/etc/network/interfaces
check_command $? "Transferring network configuration file"

# Update the nameserver
echo "Updating nameserver to 1.1.1.1..."

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
check_command $? "Updating nameserver"

echo "Network configuration updated."

# Gracefully shutdown the VM
echo "Gracefully shutting down the VM..."

echo "Executing: printf 'system_powerdown\\n' | nc 127.0.0.1 4444"
printf "system_powerdown\n" | nc 127.0.0.1 4444

# Wait for VM to shut down
echo "Waiting for the VM to shut down..."
sleep 30  # Adjust the time as needed

echo ""
echo "========================================================================="
echo "The VM has been shut down."
echo "We are now ready to boot directly into Proxmox VE."
echo "The system will now reboot and exit the Rescue System."
echo "========================================================================="
echo ""

# Final confirmation before rebooting
read -p "Are you sure you want to reboot the system now? (y/n): " reboot_confirm
if [[ $reboot_confirm != "y" ]]; then
    echo "Reboot aborted."
    exit 1
fi

# Flush file system buffers
echo "Flushing file system buffers..."
sync

echo "Rebooting the system..."

shutdown -r now
