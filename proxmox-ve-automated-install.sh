#!/bin/bash

# ==============================================================================
# Proxmox Install Script with Enhanced UX/UI
# ==============================================================================

# -------------------------------
# Color Definitions
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# -------------------------------
# Spinner Function for Progress Indication
# -------------------------------
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# -------------------------------
# Ensure the script is run with root privileges
# -------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

# -------------------------------
# Function to check command success
# -------------------------------
check_command() {
    if [[ $1 -ne 0 ]]; then
        echo -e "${RED}Error: $2 failed.${NC}"
        exit 1
    fi
}

# -------------------------------
# Welcome Message
# -------------------------------
echo -e "${CYAN}Welcome to the Proxmox Install Script for Dedicated Servers...${NC}"
sleep 1

# -------------------------------
# Downloading Proxmox VE
# -------------------------------
echo -e "${YELLOW}Downloading Proxmox VE...${NC}"

# Retrieve the latest Proxmox VE ISO using HTTP
ISO_VERSION=$(curl -s 'http://download.proxmox.com/iso/' | grep -oP 'proxmox-ve_\d+\.\d+-\d+\.iso' | sort -V | tail -n1)
ISO_URL="http://download.proxmox.com/iso/$ISO_VERSION"

if [[ -z "$ISO_VERSION" ]]; then
    echo -e "${RED}Failed to retrieve the Proxmox VE ISO version.${NC}"
    exit 1
fi

echo -e "${GREEN}Latest Proxmox VE ISO Version: $ISO_VERSION${NC}"
echo -e "${GREEN}ISO URL: $ISO_URL${NC}"

# Check if the ISO file already exists
if [[ -f /tmp/proxmox-ve.iso ]]; then
    while true; do
        read -p "$(echo -e "${YELLOW}The file /tmp/proxmox-ve.iso already exists. Do you want to overwrite it? (y/n): ${NC}")" overwrite
        case $overwrite in
            [Yy]* )
                echo -e "${MAGENTA}Deleting existing file and downloading a new one...${NC}"
                rm /tmp/proxmox-ve.iso &
                spinner $!
                check_command $? "Deleting existing ISO file"

                echo -e "${MAGENTA}Downloading the Proxmox VE ISO. This may take a while...${NC}"
                curl -o /tmp/proxmox-ve.iso "$ISO_URL" &
                spinner $!
                check_command $? "Downloading Proxmox VE ISO"
                break
                ;;
            [Nn]* )
                echo -e "${GREEN}Skipping download and proceeding with the existing ISO.${NC}"
                break
                ;;
            * ) echo -e "${RED}Please answer y or n.${NC}";;
        esac
    done
else
    # If file does not exist, download the ISO
    echo -e "${MAGENTA}Downloading the Proxmox VE ISO. This may take a while...${NC}"
    curl -o /tmp/proxmox-ve.iso "$ISO_URL" &
    spinner $!
    check_command $? "Downloading Proxmox VE ISO"
fi

# -------------------------------
# Acquire Network Configuration
# -------------------------------
echo -e "${YELLOW}Acquiring Network Configuration...${NC}"

# Get the network interface name
INTERFACE_NAME=$(ip route | grep default | awk '{print $5}')

if [[ -z "$INTERFACE_NAME" ]]; then
    echo -e "${RED}Failed to detect the network interface.${NC}"
    exit 1
fi

IP_CIDR=$(ip addr show "$INTERFACE_NAME" | grep "inet\b" | awk '{print $2}')
GATEWAY=$(ip route | grep default | awk '{print $3}')
IP_ADDRESS=$(echo "$IP_CIDR" | cut -d'/' -f1)
CIDR=$(echo "$IP_CIDR" | cut -d'/' -f2)

echo -e "${GREEN}Interface Name: $INTERFACE_NAME${NC}"
echo -e "${GREEN}IP Address: $IP_ADDRESS${NC}"
echo -e "${GREEN}CIDR: $CIDR${NC}"
echo -e "${GREEN}Gateway: $GATEWAY${NC}"

# Confirm network settings
while true; do
    read -p "$(echo -e "${YELLOW}Proceed with these network settings? (y/n): ${NC}")" proceed
    case $proceed in
        [Yy]* ) break;;
        [Nn]* )
            echo -e "${RED}Aborted.${NC}"
            exit 1;;
        * ) echo -e "${RED}Please answer y or n.${NC}";;
    esac
done

# -------------------------------
# Ask for Boot Mode
# -------------------------------
while true; do
    echo -e "${YELLOW}Do you want to install Proxmox in UEFI mode? (recommended for most systems)${NC}"
    read -p "$(echo -e "${YELLOW}Enter 'y' for UEFI mode or 'n' for Legacy mode: ${NC}")" uefi_choice
    case $uefi_choice in
        [Yy]* ) BOOT_MODE="UEFI"; break;;
        [Nn]* ) BOOT_MODE="Legacy"; break;;
        * ) echo -e "${RED}Please answer y or n.${NC}";;
    esac
done

echo -e "${GREEN}Selected boot mode: $BOOT_MODE${NC}"

# -------------------------------
# Get the List of Disks
# -------------------------------
DISK_LIST=($(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk" {print $1}'))

if [[ ${#DISK_LIST[@]} -eq 0 ]]; then
    echo -e "${RED}No disks found.${NC}"
    exit 1
fi

echo -e "${CYAN}Available disks:${NC}"
for i in "${!DISK_LIST[@]}"; do
    DISK_NAME=${DISK_LIST[$i]}
    DISK_SIZE=$(lsblk -dn -o SIZE "/dev/$DISK_NAME")
    echo -e "${BLUE}$((i+1))) /dev/$DISK_NAME - $DISK_SIZE${NC}"
done

# -------------------------------
# Validate Primary Disk Selection
# -------------------------------
while true; do
    read -p "$(echo -e "${YELLOW}Enter the number corresponding to the primary disk: ${NC}")" primary_choice
    if [[ "$primary_choice" =~ ^[0-9]+$ && $primary_choice -ge 1 && $primary_choice -le ${#DISK_LIST[@]} ]]; then
        PRIMARY_DISK=${DISK_LIST[$((primary_choice-1))]}
        break
    else
        echo -e "${RED}Invalid input. Please enter a valid disk number.${NC}"
    fi
done

# -------------------------------
# Validate Secondary Disk Selection
# -------------------------------
while true; do
    read -p "$(echo -e "${YELLOW}Enter the number corresponding to the secondary disk (or press Enter to skip): ${NC}")" secondary_choice
    if [[ -z "$secondary_choice" ]]; then
        SECONDARY_DISK=""
        break
    elif [[ "$secondary_choice" =~ ^[0-9]+$ && $secondary_choice -ge 1 && $secondary_choice -le ${#DISK_LIST[@]} ]]; then
        SECONDARY_DISK=${DISK_LIST[$((secondary_choice-1))]}
        break
    else
        echo -e "${RED}Invalid input. Please enter a valid disk number.${NC}"
    fi
done

echo -e "${RED}WARNING: The selected disks will be completely erased during the installation.${NC}"
echo -e "${GREEN}Primary Disk: /dev/$PRIMARY_DISK${NC}"
if [[ -n "$SECONDARY_DISK" ]]; then
    echo -e "${GREEN}Secondary Disk: /dev/$SECONDARY_DISK${NC}"
else
    echo -e "${GREEN}No Secondary Disk selected.${NC}"
fi

# Confirm disk selection
while true; do
    read -p "$(echo -e "${YELLOW}Are you sure you want to proceed with these disks? (y/n): ${NC}")" confirm
    case $confirm in
        [Yy]* ) break;;
        [Nn]* )
            echo -e "${RED}Operation aborted.${NC}"
            exit 1;;
        * ) echo -e "${RED}Please answer y or n.${NC}";;
    esac
done

# -------------------------------
# Check for Required Packages
# -------------------------------
echo -e "${YELLOW}Checking for required packages...${NC}"
REQUIRED_PACKAGES=(qemu-kvm ovmf netcat sshpass)
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$pkg"; then
        echo -e "${MAGENTA}Installing $pkg...${NC}"
        apt-get update &
        spinner $!
        apt-get install -y "$pkg" &
        spinner $!
        check_command $? "Installing $pkg"
    else
        echo -e "${GREEN}$pkg is already installed.${NC}"
    fi
done

# -------------------------------
# Set VNC Password with Validation
# -------------------------------
while true; do
    echo -e "${CYAN}Please enter VNC password (maximum 8 characters):${NC}"
    read -s VNC_PASSWORD1
    echo
    if [[ ${#VNC_PASSWORD1} -gt 8 ]]; then
        echo -e "${RED}Password is too long. It must be 8 characters or less. Please try again.${NC}"
        continue
    fi

    echo -e "${CYAN}Please confirm VNC password:${NC}"
    read -s VNC_PASSWORD2
    echo

    if [[ "$VNC_PASSWORD1" == "$VNC_PASSWORD2" ]]; then
        VNC_PASSWORD="$VNC_PASSWORD1"
        break
    else
        echo -e "${RED}Passwords do not match. Please try again.${NC}"
    fi
done

# -------------------------------
# Start QEMU for Proxmox Installation
# -------------------------------
if [[ $BOOT_MODE == "UEFI" ]]; then
    echo -e "${YELLOW}Starting QEMU in UEFI mode with CDROM...${NC}"

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
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait &
else
    echo -e "${YELLOW}Starting QEMU in Legacy mode with CDROM...${NC}"

    # Prepare disk options
    DISK_OPTIONS="-hda /dev/$PRIMARY_DISK"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -hdb /dev/$SECONDARY_DISK"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -cdrom /tmp/proxmox-ve.iso -boot d \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait &
fi
check_command $? "Starting QEMU for Proxmox installation"

# -------------------------------
# Wait for QEMU Monitor to be Available
# -------------------------------
echo -e "${YELLOW}Waiting for QEMU monitor to be available...${NC}"
for i in {1..10}; do
    if nc -z 127.0.0.1 4444; then
        echo -e "${GREEN}QEMU monitor is available.${NC}"
        break
    else
        echo -e "${MAGENTA}QEMU monitor not available yet. Retrying in 3 seconds...${NC}"
        sleep 3
    fi
done

if ! nc -z 127.0.0.1 4444; then
    echo -e "${RED}Failed to connect to QEMU monitor.${NC}"
    exit 1
fi

# -------------------------------
# Set VNC Password
# -------------------------------
echo -e "${CYAN}Setting VNC password...${NC}"
echo "change vnc password $VNC_PASSWORD" | nc -q 1 127.0.0.1 4444

echo ""
echo -e "${MAGENTA}=========================================================================${NC}"
echo -e "${GREEN}VNC server is running on port 5900 (display :0)${NC}"
echo -e "${GREEN}You can now connect via VNC to proceed with the Proxmox installation.${NC}"
echo ""
echo -e "${GREEN}Please follow these steps to install Proxmox VE via the GUI:${NC}"
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
echo -e "${MAGENTA}=========================================================================${NC}"
echo ""

# -------------------------------
# Confirmation Prompts
# -------------------------------
read -p "$(echo -e "${YELLOW}Have you completed the Proxmox VE installation and are ready to continue? (y/n): ${NC}")" proceed
if [[ $proceed != [Yy]* ]]; then
    echo -e "${RED}Please complete the installation before proceeding.${NC}"
    exit 1
fi

read -p "$(echo -e "${YELLOW}Are you absolutely sure you want to continue? This action is irreversible. (y/n): ${NC}")" confirm
if [[ $confirm != [Yy]* ]]; then
    echo -e "${RED}Operation aborted.${NC}"
    exit 1
fi

echo -e "${GREEN}Continuing with the next steps...${NC}"

# -------------------------------
# Stop Initial QEMU Session
# -------------------------------
echo -e "${YELLOW}Closing the initial QEMU session...${NC}"
echo "quit" | nc 127.0.0.1 4444 &
spinner $!
check_command $? "Closing initial QEMU session"

# Confirm QEMU has stopped
echo -e "${YELLOW}Waiting for QEMU to stop...${NC}"
sleep 5

# -------------------------------
# Start QEMU to Boot from Internal Drive
# -------------------------------
echo -e "${YELLOW}Starting QEMU to boot from the internal drive...${NC}"

if [[ $BOOT_MODE == "UEFI" ]]; then
    echo -e "${YELLOW}Starting QEMU in UEFI mode without CDROM...${NC}"

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
    -net user,hostfwd=tcp::2222-:22 -net nic &
else
    echo -e "${YELLOW}Starting QEMU in Legacy mode without CDROM...${NC}"

    # Prepare disk options
    DISK_OPTIONS="-hda /dev/$PRIMARY_DISK"
    if [[ -n "$SECONDARY_DISK" ]]; then
        DISK_OPTIONS+=" -hdb /dev/$SECONDARY_DISK"
    fi

    # Start QEMU
    qemu-system-x86_64 -daemonize -enable-kvm -m 10240 -k en-us \
    $DISK_OPTIONS \
    -vnc :0,password=on -monitor telnet:127.0.0.1:4444,server,nowait \
    -net user,hostfwd=tcp::2222-:22 -net nic &
fi
check_command $? "Starting QEMU to boot from internal drive"

# -------------------------------
# Set VNC Password Again
# -------------------------------
echo -e "${CYAN}Setting VNC password again...${NC}"

# Wait for QEMU monitor to be available
echo -e "${YELLOW}Waiting for QEMU monitor to be available...${NC}"
for i in {1..10}; do
    if nc -z 127.0.0.1 4444; then
        echo -e "${GREEN}QEMU monitor is available.${NC}"
        break
    else
        echo -e "${MAGENTA}QEMU monitor not available yet. Retrying in 3 seconds...${NC}"
        sleep 3
    fi
done

if ! nc -z 127.0.0.1 4444; then
    echo -e "${RED}Failed to connect to QEMU monitor.${NC}"
    exit 1
fi

# Set VNC password
echo -e "${CYAN}Setting VNC password...${NC}"
echo "change vnc password $VNC_PASSWORD" | nc -q 1 127.0.0.1 4444

echo ""
echo -e "${MAGENTA}=========================================================================${NC}"
echo -e "${GREEN}QEMU is running, and you can connect back via VNC to $IP_ADDRESS:5900.${NC}"
echo -e "${GREEN}Please wait for the Proxmox VE system to boot.${NC}"
echo -e "${MAGENTA}=========================================================================${NC}"
echo ""

# -------------------------------
# Wait for the VM to Boot Up
# -------------------------------
echo -e "${YELLOW}Waiting for the VM to boot up...${NC}"
sleep 60  # Adjust the time as needed based on your system

# -------------------------------
# Prompt for the Root Password Set During Installation
# -------------------------------
echo -e "${CYAN}Please enter the root password you set during the Proxmox installation:${NC}"
read -s ROOT_PASSWORD
echo -e "${CYAN}Please confirm the root password:${NC}"
read -s ROOT_PASSWORD_CONFIRM
echo

if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
    echo -e "${RED}Passwords do not match. Exiting.${NC}"
    exit 1
fi

# -------------------------------
# Verify SSH Connectivity to the VM
# -------------------------------
echo -e "${YELLOW}Verifying SSH connectivity to the VM...${NC}"
for i in {1..10}; do
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'SSH connection successful'" && break
    echo -e "${MAGENTA}SSH not available yet. Retrying in 10 seconds...${NC}"
    sleep 10
done

if ! sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'SSH connection successful'"; then
    echo -e "${RED}Failed to establish SSH connection to the VM.${NC}"
    exit 1
fi

# -------------------------------
# Create Network Configuration File
# -------------------------------
echo -e "${YELLOW}Creating network configuration file...${NC}"

# Get the interface name that Proxmox will use
PROXMOX_INTERFACE_NAME=$(udevadm info -q all -p /sys/class/net/$INTERFACE_NAME | grep ID_NET_NAME_PATH | cut -d'=' -f2)

# Fallback to the detected interface name if ID_NET_NAME_PATH is not available
if [[ -z "$PROXMOX_INTERFACE_NAME" ]]; then
    PROXMOX_INTERFACE_NAME="$INTERFACE_NAME"
fi

# Get the MAC address of the interface
MAC_ADDRESS=$(ip link show "$INTERFACE_NAME" | awk '/ether/ {print $2}')

cat > /tmp/proxmox_network_config << EOF
auto lo
iface lo inet loopback

iface $PROXMOX_INTERFACE_NAME inet manual

auto vmbr0
iface vmbr0 inet static
    address $IP_ADDRESS/$CIDR
    gateway $GATEWAY
    bridge_ports $PROXMOX_INTERFACE_NAME
    bridge_stp off
    bridge_fd 0
    hwaddress $MAC_ADDRESS
EOF

echo -e "${GREEN}Network configuration file created at /tmp/proxmox_network_config${NC}"
echo ""
echo -e "${GREEN}Contents:${NC}"
cat /tmp/proxmox_network_config
echo ""

read -p "$(echo -e "${YELLOW}Proceed to transfer the network configuration to Proxmox VE system? (y/n): ${NC}")" proceed
if [[ $proceed != [Yy]* ]]; then
    echo -e "${RED}Operation aborted.${NC}"
    exit 1
fi

# -------------------------------
# Transfer the Network Configuration File to Proxmox VE System
# -------------------------------
echo -e "${YELLOW}Transferring network configuration to Proxmox VE system...${NC}"

sshpass -p "$ROOT_PASSWORD" scp -o StrictHostKeyChecking=no -P 2222 /tmp/proxmox_network_config root@localhost:/etc/network/interfaces &
spinner $!
check_command $? "Transferring network configuration file"

# -------------------------------
# Update the Nameserver
# -------------------------------
echo -e "${YELLOW}Updating nameserver to 1.1.1.1...${NC}"

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'nameserver 1.1.1.1' > /etc/resolv.conf" &
spinner $!
check_command $? "Updating nameserver"

echo -e "${GREEN}Network configuration updated.${NC}"

# -------------------------------
# Gracefully Shutdown the VM
# -------------------------------
echo -e "${YELLOW}Gracefully shutting down the VM...${NC}"

echo "system_powerdown" | nc 127.0.0.1 4444 &
spinner $!
check_command $? "Gracefully shutting down the VM"

# Wait for VM to shut down
echo -e "${YELLOW}Waiting for the VM to shut down...${NC}"
sleep 30  # Adjust the time as needed

echo ""
echo -e "${MAGENTA}=========================================================================${NC}"
echo -e "${GREEN}The VM has been shut down.${NC}"
echo -e "${GREEN}We are now ready to boot directly into Proxmox VE.${NC}"
echo -e "${GREEN}The system will now reboot and exit the Rescue System.${NC}"
echo -e "${MAGENTA}=========================================================================${NC}"
echo ""

# -------------------------------
# Final Confirmation Before Rebooting
# -------------------------------
read -p "$(echo -e "${YELLOW}Are you sure you want to reboot the system now? (y/n): ${NC}")" reboot_confirm
if [[ $reboot_confirm != [Yy]* ]]; then
    echo -e "${RED}Reboot aborted.${NC}"
    exit 1
fi

# Flush file system buffers
echo -e "${YELLOW}Flushing file system buffers...${NC}"
sync

echo -e "${GREEN}Rebooting the system...${NC}"
shutdown -r now
