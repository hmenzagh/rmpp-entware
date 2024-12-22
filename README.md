# RMPP Entware

**RMPP Entware** allows you to install additional software packages from the [Entware](https://github.com/Entware/Entware) repositories on your reMarkable device. This enhances your device's functionality through a lightweight package manager designed for embedded systems.

> **Special Thanks:**  
> I extend my gratitude to [Evidlo](https://github.com/Evidlo) for his original work on [remarkable_entware](https://github.com/Evidlo/remarkable_entware), which served as the foundation to this script.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Step 1: Connect Your reMarkable](#step-1-connect-your-remarkable)
  - [Step 2: Access via SSH](#step-2-access-via-ssh)
  - [Step 3: Run the Installer](#step-3-run-the-installer)
- [Usage](#usage)
  - [Installing Packages](#installing-packages)
  - [Searching for Packages](#searching-for-packages)
- [Managing Updates](#managing-updates)
  - [After a Firmware Update](#after-a-firmware-update)
- [Cleanup](#cleanup)
- [Real-World Use Cases](#real-world-use-cases)
- [Additional Information](#additional-information)
  - [PATH Configuration](#path-configuration)
  - [Toltec Compatibility](#toltec-compatibility)
- [Managing Packages with Opkg](#managing-packages-with-opkg)
- [Final Notes](#final-notes)
  - [System Compatibility](#system-compatibility)
  - [Safety Precautions](#safety-precautions)
  - [Support Disclaimer](#support-disclaimer)
- [Support](#support)

## Features

- **Extended Functionality:** Install a wide range of packages from Entware repositories.
- **RMPP Support:** Tailored for devices running the RMPP firmware.
- **Persistent Installation:** Remains intact even after firmware updates.

## Prerequisites

Before installing reMarkable Entware, ensure you have the following:

- **reMarkable Device:** Ensure your device is running the RMPP firmware.
- **USB Connection:** A USB cable to connect your reMarkable to your computer.
- **Internet Access:** The device must be connected to the internet.
- **SSH Access:** Ability to access your device via SSH.

## Installation

Follow these steps to install reMarkable Entware on your device.

### Step 1: Connect Your reMarkable

1. **Connect via USB:** Use a USB cable to connect your reMarkable device to your computer.
2. **Ensure Internet Access:** Verify that your device is connected to the internet to download necessary packages.

### Step 2: Access via SSH

1. **Enable SSH:** If not already enabled, follow [these instructions](https://remarkable.guide/guide/access/index.html) to enable SSH on your reMarkable (dev mode).
2. **Connect to SSH:** Use an SSH client to connect to your device. For example:
   ```bash
   ssh root@<your-device-ip>
   ```

### Step 3: Run the Installer

Execute the installation script to set up Entware on your device.

#### Standard Installation

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash
```

#### Force Installation (Bypass Prompts)

If you prefer a non-interactive installation that automatically answers to prompts:

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --force
```

#### Cleanup Installation (Remove Existing Entware)

To remove any partial or existing Entware installation:

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --cleanup
```

##### Force Cleanup (No Prompts)

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --cleanup --force
```

#### Re-enable Entware After Firmware Update

> **Warning:** This part of the script has not been tested yet & may not work as expected.
After updating your device's firmware, Entware remains safe in `/home/root/.entware`. To remount `/opt` and re-enable Entware:

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --reenable
```

##### Force Re-enable (No Prompts)

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --reenable --force
```

> **Note:** The base installation requires approximately **13MB** of space. All Entware data is stored in `/opt`, which is bind-mounted to `/home/root/.entware` to optimize space usage on the root partition.

## Usage

Once installed, you can manage packages using the `opkg` package manager.

### Installing Packages

To install a package, use the following command:

```bash
opkg install <package_name>
```

**Example: Install Git**

```bash
opkg install git
```

### Searching for Packages

To search for available packages, use:

```bash
opkg find '<search_term>'
```

**Example: Search for Packages Related to 'top'**

```bash
opkg find '*top*'
```

## Managing Updates

### After a Firmware Update

Firmware updates might overwrite data outside `/home/root`. However, Entware remains safe in `/home/root/.entware`. To ensure Entware remains functional:

1. **Remount `/opt`:**

   ```bash
   wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --reenable
   ```

2. **Force Re-enable (No Prompts):**

   ```bash
   wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --reenable --force
   ```

## Cleanup

If you need to remove Entware from your device, follow these steps.

### Remove Entware

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --cleanup
```

#### Force Cleanup (No Prompts)

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --cleanup --force
```

### Free Up Disk Space

To free up space on the root partition by cleaning up system logs:

```bash
journalctl --vacuum-size=2M
```

## Additional Information

### PATH Configuration

During installation, the script can automatically add `/opt/bin` and `/opt/sbin` to your `PATH`. If you skipped this step or used the `--force` option, you can manually update your `PATH`:

1. **Add to PATH:**

   ```bash
   export PATH=/opt/bin:/opt/sbin:$PATH
   ```

2. **Apply Changes:**

   ```bash
   source ~/.bashrc
   ```

### Toltec Compatibility

- **Compatibility Limitation:** [Toltec](https://github.com/toltec-dev/toltec) is not supported on firmware versions above **3.3.2.1666** (as of 2024-12-22).
- **RMPP Users:** Toltec is currently not viable for RMPP users.

## Managing Packages with Opkg

Use `opkg` to manage your Entware packages effectively.

### Update Package List

```bash
opkg update
```

### Install a Package

```bash
opkg install <package_name>
```

### Remove a Package

```bash
opkg remove <package_name>
```

### Upgrade Installed Packages

```bash
opkg upgrade
```

## Final Notes

### System Compatibility

- **Supported Devices:** This installer is specifically designed for **RMPP** devices.
  
### Safety Precautions

- **Avoid Interruptions:** Do not power off your device during the installation process to prevent potential system corruption.

### Support Disclaimer

- **Use at Your Own Risk:** I am not responsible for any damage or issues arising from the use of this software.
- **No Guaranteed Support:** While I will try to help & update the script, support is limited.

**Happy hacking!**

For more detailed information about script usage and available options, run:

```bash
wget -O - http://raw.githubusercontent.com/hmenzagh/rmpp-entware/main/rmpp_entware.sh | bash -s -- --help
```

## Support

If you encounter issues or have questions, consider the following resources:
- **Documentation:** Refer to the [Entware Wiki](https://github.com/Entware/Entware/wiki) for comprehensive guides.
- **Remarkable.Guide:** [reMarkable.Guide](https://remarkable.guide/) is a great resource to learn more about the reMarkable devices.

---

**Disclaimer:** Always ensure you have backups of important data before making significant changes to your device. Proceed with caution and at your own risk.
