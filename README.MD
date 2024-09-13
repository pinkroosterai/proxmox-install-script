# Proxmox VE Automated Installation Script

This script automates the installation of Proxmox VE on a dedicated server by leveraging QEMU virtualization within a rescue system environment. It was **made and tested on a Hetzner dedicated server**, but it should work on most hosted dedicated servers with similar configurations.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Connecting to the Rescue System](#connecting-to-the-rescue-system)
- [Warnings and Disclaimers](#warnings-and-disclaimers)
- [Usage Instructions](#usage-instructions)
- [Script Overview](#script-overview)
- [Post-Installation Steps](#post-installation-steps)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- Downloads the latest Proxmox VE ISO securely using HTTPS.
- Allows manual selection of primary and secondary disks for installation.
- Automates the Proxmox VE installation process via a VNC session.
- Configures network interfaces for Proxmox VE.
- Transfers network configuration to the Proxmox VE system.
- Gracefully shuts down the virtual machine and reboots into Proxmox VE.

## Prerequisites

- A dedicated server with root access running a rescue system (e.g., provided by your hosting provider).
- Internet connectivity to download the Proxmox VE ISO and required packages.
- A VNC viewer application (e.g., RealVNC, TightVNC) installed on your local machine.
- Basic understanding of Linux command-line operations.

## Connecting to the Rescue System

Before running the script, you'll need to boot your server into a **rescue system** (also known as recovery mode). Here's how to connect to the rescue system, specifically on a **Hetzner dedicated server**. These steps should be similar for other hosting providers that offer a rescue environment.

### Steps to Access the Rescue System on Hetzner:

1. **Activate Rescue System from Hetzner Robot:**
   - Log in to your Hetzner Robot dashboard: [Hetzner Robot](https://robot.your-server.de).
   - Select your dedicated server from the list.
   - Under the "Rescue" tab, activate the rescue system.
   - Select the **Linux 64-bit rescue image**.
   - Set or note down the rescue system password (you can also generate a new one if needed).
   - Click **Activate Rescue System**.

2. **Reboot Your Server into the Rescue System:**
   - After activating the rescue system, go to the "Reset" tab in Hetzner Robot.
   - Click **Execute hardware reset** to reboot your server into the rescue system.

3. **Connect via SSH:**
   - Once the server reboots into the rescue system, you should receive an email from Hetzner with SSH connection details (your server's IP address and the root password).
   - Open your terminal and connect to the server using SSH:
   
     ```bash
     ssh root@YOUR_SERVER_IP
     ```

   - Replace `YOUR_SERVER_IP` with your actual server's IP address.
   - When prompted, enter the rescue system password.

4. **Verify Rescue System:**
   - Once logged in, verify that you are in the rescue system by running the following command:
   
     ```bash
     uname -a
     ```
   
   - It should display information about the Linux rescue environment.

### Steps for Other Providers:

If you're using a hosting provider other than Hetzner, the general process to access the rescue system should be similar:

1. Log in to your hosting provider's management dashboard.
2. Locate the option to boot into the rescue or recovery system.
3. Follow the steps to activate the rescue mode and reboot your server.
4. Connect to the server via SSH using the provided credentials or root password.

Once you are connected to the rescue system, you can proceed with the [Usage Instructions](#usage-instructions).

## ⚠️ Warnings and Disclaimers

- **⚠️ Data Loss Warning:** This script will **erase all data** on the selected disks. Ensure you have backups of any important data before proceeding.
- **⚠️ Use at Your Own Risk:** This script is provided "as is" without warranty of any kind. The use of this script is at your own risk.
- **🛠 Testing Recommendation:** It is strongly recommended to test this script in a non-production environment before using it on critical systems.
- **🔐 Security Considerations:** The script uses passwords in plaintext for automation purposes. Ensure the script is stored securely and deleted after use.

## Usage Instructions

### 1. Download and Prepare the Script

- Save the script to your server with the filename `install_proxmox.sh`:

  ```bash
  nano install_proxmox.sh
  ```

  Paste the script content into the file, then save and exit.

- Make the script executable:

  ```bash
  chmod +x install_proxmox.sh
  ```

### 2. Run the Script

- Execute the script with root privileges:

  ```bash
  ./install_proxmox.sh
  ```

- The script will prompt you for input at various stages. Follow the on-screen instructions carefully.

### 3. ⚠️ Select Disks for Installation

- The script will display a list of available disks.
- Enter the number corresponding to the primary disk you wish to use.
- Optionally, enter the number for a secondary disk (e.g., for RAID configurations).

### 4. Provide Network Configuration Confirmation

- Review the detected network settings (interface name, IP address, CIDR, gateway).
- Confirm if you wish to proceed with these settings.

### 5. Choose Boot Mode

- Select whether to install Proxmox VE in **UEFI** mode (recommended) or **Legacy** mode.

### 6. Set VNC Password

- Enter and confirm a VNC password (maximum 8 characters). This will be used to connect to the virtual machine during installation.

### 7. Install Proxmox VE via VNC

- Connect your VNC viewer to `YOUR_SERVER_IP:5900` using the password you set.
- Follow the Proxmox VE installer steps:
  - Select **Install Proxmox VE (Graphical)**.
  - Agree to the license terms.
  - Choose your disk configuration (e.g., ZFS RAID1).
  - Set your country, time zone, and keyboard layout.
  - Enter a root password and email address (use a simple password without special symbols).
  - Leave network settings as default.
  - Uncheck **Automatically reboot after successful installation**.
  - Click **Install**.
- Once installation is complete, **⚠️ do not click Reboot**. Return to the terminal.

### 8. Continue with Post-Installation Steps

- Confirm that you have completed the Proxmox VE installation.
- The script will close the initial QEMU session and start a new one booting from the internal drive.
- Set the VNC password again when prompted.
- Wait for the Proxmox VE system to boot.

### 9. Configure Network Interfaces

- Enter the root password you set during the Proxmox VE installation.
- The script will transfer the network configuration to the Proxmox VE system.
- Confirm when prompted to proceed with transferring the configuration.

### 10. ⚠️ Finalize Installation

- The script will gracefully shut down the virtual machine.
- Confirm if you wish to reboot the system.
- The system will reboot and exit the rescue environment, booting into Proxmox VE.

## Script Overview

The script performs the following major steps:

1. **Download Proxmox VE ISO:**
   - Retrieves the latest Proxmox VE ISO version securely using HTTPS.
   - Downloads the ISO to `/tmp/proxmox-ve.iso`.

2. **Network Configuration Detection:**
   - Detects the default network interface and retrieves IP address, CIDR, and gateway.

3. **⚠️ Disk Selection:**
   - Lists available disks and allows manual selection of primary and secondary disks.
   - Provides warnings about data loss.

4. **Required Packages Installation:**
   - Checks for and installs necessary packages: `qemu-kvm`, `ovmf`, `netcat`, `sshpass`.

5. **QEMU Initialization for Proxmox VE Installation:**
   - Starts QEMU with the Proxmox VE ISO in either UEFI or Legacy mode.
   - Sets up VNC for remote installation.

6. **Proxmox VE Installation via VNC:**
   - Provides instructions to connect via VNC and complete the installation.

7. **QEMU Restart to Boot from Internal Drive:**
   - Closes the initial QEMU session.
   - Starts a new QEMU session booting from the internal drive without the ISO.

8. **Network Interfaces Configuration:**
   - Creates a network configuration file with appropriate settings.
   - Transfers the configuration to the Proxmox VE system using `scp`.
   - Updates the nameserver to `1.1.1.1`.

9. **⚠️ Finalization:**
   - Gracefully shuts down the virtual machine.
   - Flushes file system buffers.
   - Reboots the system into Proxmox VE.

## Post-Installation Steps

After the server reboots:

1. **Access Proxmox VE Web Interface:**
   - Open a web browser and navigate to `https://YOUR_SERVER_IP:8006`.
   - Accept any security warnings regarding self-signed certificates.

2. **Log In to Proxmox VE:**
   - Username: `root`
   - Password: The root password you set during the installation.

3. **Complete Initial Configuration:**

   - Configure your storage, networking, and any other settings as required.
   - Update Proxmox VE to the latest version using the web interface or CLI by running:
   
     ```bash
     apt update && apt dist-upgrade
     ```

   - Ensure that any necessary packages or drivers are installed, depending on your server's hardware.

4. **Create Your First Virtual Machine or Container:**

   - Once Proxmox VE is set up, you can create virtual machines (VMs) or Linux containers (LXC) through the web interface.
   - Use the Proxmox VE documentation to guide you through the process: [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page).

## Troubleshooting

- **Cannot Connect via VNC:**
  - Ensure your firewall allows connections on port `5900`.
  - Verify that the VNC server is running (`ps aux | grep qemu`).
  - Double-check that you are connecting to the correct IP address of the server.

- **SSH Connection Fails:**
  - Confirm that the SSH service is running inside the Proxmox VE virtual machine.
  - Ensure that port forwarding is correctly set up with QEMU (`-net user,hostfwd=tcp::2222-:22`).

- **QEMU Monitor Not Available:**
  - Wait a few moments and try again; the VM might be initializing.
  - Check if QEMU is running and listening on port `4444` by running:
  
    ```bash
    netstat -tuln | grep 4444
    ```
  
  - If QEMU is not running, try restarting the process or checking for any errors in the logs.

- **Proxmox VE Web Interface Not Accessible After Reboot:**
  - Verify that the server has fully rebooted into Proxmox VE.
  - Ensure that your network configuration is correct and that the server is reachable.
  - Use `ifconfig` or `ip addr` to check the network interfaces and IP address assignments.

- **Disk Errors:**
  - If the system encounters issues with disk configuration, check the disk's health using `smartctl` or other diagnostic tools.
  - Ensure that the correct disks were selected during installation.

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/yourusername/proxmox-install-script/issues) if you want to contribute.

## License

This project is open-source and available under the [MIT License](LICENSE).

---

**Note:** Replace `YOUR_SERVER_IP` with the actual IP address of your server throughout the instructions.

**Disclaimer:** This script is intended for educational purposes. The author is not responsible for any damage or data loss resulting from the use of this script.

---

This concludes the complete setup and troubleshooting guide for installing Proxmox VE using a rescue system on a dedicated server. The script simplifies the process and aims to minimize errors, but remember to thoroughly test everything in a non-production environment before applying it to critical systems.

If you encounter any issues, refer to the troubleshooting section or consult Proxmox's official documentation for further assistance.
