#!/bin/bash
# Hugo Menzaghi - 2024-12-22
# Entware Installer & Re-enabler for RMPP Devices

#################################################################
########################### VARIABLES ###########################
#################################################################

# Exit on any error
set -e

FORCE=no
CLEANUP=no
REENABLE=no
HELP=no

# Variable to capture exit code
EXIT_CODE=0

#################################################################
########################### FUNCTIONS ###########################
#################################################################

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --help         Show this help message and exit
  --force        Run in non-interactive mode (answering to prompts with default answers)
  --cleanup      Remove Entware installation
  --reenable     Re-enable Entware after an OS update

Examples:
  $0             Install Entware
  $0 --cleanup   Uninstall/Clean up Entware
  $0 --reenable  Re-enable Entware after an OS update
  $0 --force     Perform actions without user confirmation
EOF
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root (e.g. sudo $0). Exiting..."
        exit 1
    fi
}

# Check for adequate free space (in MB) on a target mount point
check_free_space() {
    local mount_point="$1"
    local required_mb="$2"

    local available_mb
    available_mb=$(df -Pm "$mount_point" | tail -1 | awk '{print $4}')

    if [ "$available_mb" -lt "$required_mb" ]; then
        echo "Error: Not enough free space on '$mount_point'."
        echo "Available: ${available_mb}MB, Required: ${required_mb}MB."
        exit 1
    fi
}

# Manage filesystem read/write state
ensure_filesystem_rw() {
    ORIG_MOUNT_OPTS=$(awk '$2 == "/" {print $4}' /proc/mounts)
    if echo "$ORIG_MOUNT_OPTS" | grep -q "ro"; then
        if [ "$FORCE" = "yes" ]; then
            echo "Force option enabled. Remounting filesystem as read/write..."
            answer="y"
        else
            echo "Filesystem is currently read-only. Remount as read/write? (y/N)"
            read -r answer </dev/tty
        fi
        if [ "$answer" = "y" ]; then
            mount -o remount,rw /
        else
            echo "Operation canceled. Exiting..."
            exit 1
        fi
    fi
}

# Restore the original filesystem mount options
restore_filesystem_state() {
    if [ -n "$ORIG_MOUNT_OPTS" ]; then
        echo "Restoring original filesystem mount options..."
        mount -o remount,"$ORIG_MOUNT_OPTS" /
    fi
}

# Add /opt/bin and /opt/sbin to PATH in a given file
add_to_path() {
    PATH_ENTRY='export PATH=/opt/bin:/opt/sbin:$PATH'
    TARGET_FILE=$1

    # Check if the PATH entry already exists
    if ! grep -Fxq "$PATH_ENTRY" "$TARGET_FILE" 2>/dev/null; then
        echo "$PATH_ENTRY" >>"$TARGET_FILE"
        echo "Updated PATH in $TARGET_FILE."
    else
        echo "/opt/bin and /opt/sbin already in PATH for $TARGET_FILE."
    fi
}

# Write a persistent profile that auto-re-enables Entware on login after reboot.
# On RMPP devices the root filesystem is reset on reboot, so /etc/systemd/system/opt.mount
# and /etc/profile.d/entware.sh are lost. /home/root/.profile persists because it lives
# on the /home partition.
write_persistent_profile() {
    local PROFILE="/home/root/.profile"
    local MARKER_START="# >>> entware >>>"
    local MARKER_END="# <<< entware <<<"

    # Remove any existing entware block
    if [ -f "$PROFILE" ]; then
        sed -i "/$MARKER_START/,/$MARKER_END/d" "$PROFILE"
    fi

    cat >>"$PROFILE" <<'PROFILEEOF'
# >>> entware >>>
# Auto-reenable Entware after reboot (root filesystem is ephemeral on RMPP)
if [ -d /home/root/.entware/bin ] && ! mountpoint -q /opt 2>/dev/null; then
    mount -o remount,rw / 2>/dev/null
    mkdir -p /opt
    mount --bind /home/root/.entware /opt 2>/dev/null
    cat >/etc/systemd/system/opt.mount <<'UNIT'
[Unit]
Description=Bind mount over /opt to give Entware more space
DefaultDependencies=no
Conflicts=umount.target
After=home.mount
Requires=home.mount
BindsTo=home.mount

[Mount]
What=/home/root/.entware
Where=/opt
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload 2>/dev/null
    systemctl enable opt.mount 2>/dev/null
    if [ -d /etc/profile.d ]; then
        echo 'export PATH=/opt/bin:/opt/sbin:$PATH' >/etc/profile.d/entware.sh
    fi
    mount -o remount,ro / 2>/dev/null
fi
if [ -d /opt/bin ]; then
    export PATH=/opt/bin:/opt/sbin:$PATH
fi
# <<< entware <<<
PROFILEEOF

    echo "Created persistent profile at $PROFILE (survives reboots)."
}

# Checksum function
verify_checksum() {
    local file="$1"
    local expected_hash="$2"
    local computed_hash

    if [ ! -f "$file" ]; then
        echo "Error: File '$file' not found."
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        computed_hash=$(sha256sum "$file" | awk '{print $1}')
    else
        echo "Error: 'sha256sum' is not available."
        return 1
    fi

    if [ "$computed_hash" = "$expected_hash" ]; then
        echo "Checksum verification passed for $file."
        return 0
    else
        echo "Checksum verification failed for $file."
        echo "Expected: $expected_hash"
        echo "Computed: $computed_hash"
        return 1
    fi
}

# Write the systemd mount unit file for /opt
write_opt_mount_unit() {
    cat >/etc/systemd/system/opt.mount <<EOF
[Unit]
Description=Bind mount over /opt to give Entware more space
DefaultDependencies=no
Conflicts=umount.target
After=home.mount
Requires=home.mount
BindsTo=home.mount

[Mount]
What=/home/root/.entware
Where=/opt
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
EOF
}

# Cleanup function on error or abort
cleanup() {
    set +e
    trap - ERR
    if [ "$CLEANUP" = "yes" ]; then
        answer="y"
        EXIT_CODE=0
    else
        echo "An error occurred during installation."
        echo "Would you like to clean up the partial installation? (y/N)"
        if [ "$FORCE" = "yes" ]; then
            echo "Force option enabled. Proceeding with cleanup..."
            answer="y"
        else
            read -r answer </dev/tty
        fi
    fi

    if [ "$answer" = "y" ]; then
        echo "Initiating cleanup process..."

        # Ensure filesystem is read/write
        ensure_filesystem_rw

        # Disable and remove systemd mount unit
        if systemctl is-enabled opt.mount >/dev/null 2>&1; then
            systemctl disable opt.mount
            systemctl daemon-reload
        fi

        rm -f /etc/systemd/system/opt.mount
        systemctl daemon-reload

        # Unmount and remove /opt
        if mountpoint -q /opt; then
            umount /opt
        fi
        rm -rf /opt /home/root/.entware

        # Remove PATH modifications
        echo "Removing PATH modifications..."

        # Remove system-wide PATH modification
        SYSTEM_PROFILE_D="/etc/profile.d"
        ENTWARE_PROFILE="$SYSTEM_PROFILE_D/entware.sh"
        if [ -f "$ENTWARE_PROFILE" ]; then
            rm -f "$ENTWARE_PROFILE"
            echo "Removed $ENTWARE_PROFILE."
        fi

        # Remove entware entries from .profile and .bashrc
        # Handles both new-style (marker block) and old-style (bare PATH line)
        PATH_ENTRY='export PATH=/opt/bin:/opt/sbin:$PATH'
        for RCFILE in /home/root/.profile /home/root/.bashrc; do
            if [ -f "$RCFILE" ]; then
                sed -i '/# >>> entware >>>/,/# <<< entware <<</d' "$RCFILE"
                sed -i "\|$PATH_ENTRY|d" "$RCFILE"
                echo "Removed entware entries from $RCFILE."
                # Remove file if it's now empty
                if [ ! -s "$RCFILE" ]; then
                    rm -f "$RCFILE"
                    echo "Removed empty $RCFILE."
                fi
            fi
        done

        # Restore filesystem mount options
        restore_filesystem_state

        echo "Cleanup completed. Exiting..."
        exit $EXIT_CODE
    fi

    echo "Cleanup canceled. Exiting..."
    exit $EXIT_CODE
}

# Re-enable Entware function
reenable_entware() {
    echo "============================="
    echo "       ** IMPORTANT **"
    echo "This script is intended for RMPP devices only. If you are not using an RMPP device, please exit immediately."
    echo "============================="
    echo "Disclaimer:"
    echo "- **It is recommended to back up important data before proceeding.**"
    echo "- This script has been tested exclusively on firmware version v3.17.0.62."
    echo "- Do not power off the device during execution."
    echo "- The author is not liable for any potential damage caused by this script."
    echo "- Please review the script thoroughly before executing."
    echo "- No guaranteed support is provided for issues arising from this script."
    echo "============================="
    echo "This script will perform the following actions:"
    echo "- Check if Entware is already enabled and exit if it is."
    echo "- Recreate the /opt directory if missing."
    echo "- Temporarily bind /home/root/.entware to /opt."
    echo "- Create a systemd unit file to persist the bind mount across reboots."
    echo "- Enable and start the opt.mount systemd service."
    echo "============================="

    if [ "$FORCE" = "yes" ]; then
        echo "Force option enabled. Proceeding..."
    else
        echo "Press Ctrl+C to abort or press Enter to continue."
        read -r </dev/tty
    fi

    # Ensure script is run as root
    check_root

    # Check if Entware is already enabled
    if systemctl is-active opt.mount >/dev/null 2>&1; then
        echo "Entware is already enabled."
        exit 0
    fi

    # Create /opt if missing
    echo "Creating /opt directory if it doesn't exist..."
    mkdir -p /opt

    # Temporarily bind-mount /home/root/.entware to /opt
    echo "Mounting /home/root/.entware to /opt..."
    mount --bind /home/root/.entware /opt

    # Create the systemd mount unit for /opt
    echo "Creating systemd unit for /opt mount..."
    write_opt_mount_unit

    # Reload systemd configuration
    echo "Reloading systemd configuration..."
    systemctl daemon-reload

    # Enable the systemd mount unit for persistence
    echo "Enabling opt.mount for persistence..."
    systemctl enable opt.mount

    # Start the opt.mount service to bind /opt immediately
    echo "Starting opt.mount service..."
    systemctl start opt.mount

    # Ensure persistent profile exists for future reboots
    write_persistent_profile

    echo ""
    echo "Info: Entware has been successfully re-enabled."
    exit 0
}

#################################################################
########################### MAIN LOGIC ##########################
#################################################################

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
    --help)
        HELP=yes
        ;;
    --force)
        FORCE=yes
        ;;
    --cleanup)
        CLEANUP=yes
        ;;
    --reenable)
        REENABLE=yes
        ;;
    *)
        echo "Error: Unknown option '$1'."
        exit 1
        ;;
    esac
    shift
done

# Show help and exit
if [ "$HELP" = "yes" ]; then
    usage
    exit 0
fi

# Re-enable Entware if requested
if [ "$REENABLE" = "yes" ]; then
    reenable_entware
    exit 0
fi

# Trap errors to trigger cleanup
trap 'EXIT_CODE=$?; cleanup' ERR

# Unset potentially conflicting environment variables
unset LD_LIBRARY_PATH LD_PRELOAD

# Ensure script is run as root
check_root

# Handle --cleanup option
if [ "$CLEANUP" = "yes" ]; then
    echo ""
    echo "================================="
    echo "      ** CLEANUP MODE **"
    echo "This will:"
    echo "- remove all Entware packages and configuration files."
    echo "- remove the Entware directory."
    echo "- remove the Entware mount point."
    echo "- remove the Entware systemd mount unit."
    echo "- restore the original filesystem mount options."
    echo "================================="
    echo "Press Ctrl+C to abort or press Enter to continue and clean up Entware."
    if [ "$FORCE" = "yes" ]; then
        echo "Force option enabled. Proceeding..."
    else
        read -r </dev/tty
    fi
    EXIT_CODE=0
    cleanup
    exit 0
fi

#################################################################
####################### INSTALLATION FLOW #######################
#################################################################

echo "============================="
echo "       ** IMPORTANT **"
echo "This script is intended for RMPP devices only. If you are not using an RMPP device, please exit immediately."
echo "============================="
echo "Disclaimer:"
echo "- **It is recommended to back up important data before proceeding.**"
echo "- This script has been tested exclusively on firmware version v3.17.0.62."
echo "- Do not power off the device during execution."
echo "- The author is not liable for any potential damage caused by this script."
echo "- Please review the script thoroughly before executing."
echo "- No guaranteed support is provided for issues arising from this script."
echo "============================="
echo "This script will perform the following actions:"
echo "- Create /opt and /home/root/.entware directories."
echo "- Manage /opt via systemd (bind mount from /home/root/.entware)."
echo "- Deploy the Opkg package manager."
echo "- Ensure wget points to the SSL version (if installed)."
echo "- Create symbolic links for standard files."
echo "- Optionally add /opt/bin and /opt/sbin to PATH."
echo "============================="
echo "Press Ctrl+C to abort or press Enter to continue and install Entware."
if [ "$FORCE" = "yes" ]; then
    echo "Force option enabled. Proceeding..."
else
    read -r </dev/tty
fi

echo "Verifying prerequisites..."

check_free_space "/home/root" "50"
ensure_filesystem_rw

# Check existing installation
if [ -d /opt ] || [ -d /home/root/.entware ]; then
    echo "Error: /opt or /home/root/.entware already exists."
    EXIT_CODE=1
    cleanup
fi

mkdir -p /opt /home/root/.entware

# Create systemd mount unit for /opt
echo "Creating systemd unit for /opt mount..."
write_opt_mount_unit
systemctl daemon-reload
systemctl enable opt.mount
systemctl start opt.mount

for folder in bin etc lib/opkg tmp var/lock; do
    mkdir -p "/opt/$folder"
done

echo "Deploying Opkg package manager..."

URL=http://bin.entware.net/aarch64-k3.10/installer
declare -A files=(
    ["opkg"]="1c59274bd25080b869f376788795f5319d0d22e91f325f74ce98a7d596f68015"
    ["opkg.conf"]="07e6807fd6b505d24cdb8c0efa8fe7af064a778259d2e93bb5728396a8cdc485"
    ["ld-2.27.so"]="97fe30cc3f431b3794d27135022f68ded63fca0bb234bf65487a5d7bbf18f828"
    ["libc-2.27.so"]="58e988f2f64ea92489b93b33b27735a623859babf69ac4cd2a1cec7e85f18722"
    ["libgcc_s.so.1"]="c0deb9378520fb8d7b1269fdf106a00f78b67a88c39367a1fdd2636bded33749"
)

for filename in "${!files[@]}"; do
    url="$URL/$filename"
    destination="/opt/lib/$filename"

    case "$filename" in
    opkg)
        destination="/opt/bin/$filename"
        ;;
    opkg.conf)
        destination="/opt/etc/$filename"
        ;;
    esac

    echo "Downloading $filename..."
    wget "$url" -O "$destination"

    echo "Verifying checksum for $filename..."
    if ! verify_checksum "$destination" "${files[$filename]}"; then
        echo "Checksum verification failed for $filename. (Cached checksum: ${files[$filename]})"
        echo "Would you like to proceed anyway? (y/N)"
        if [ "$FORCE" = "yes" ]; then
            echo "Force option enabled. Aborting for safety..."
            answer="n"
        else
            read -r answer </dev/tty
        fi
        if [ "$answer" != "y" ]; then
            echo "Installation aborted."
            EXIT_CODE=1
            cleanup
        fi
    fi

    # Set permissions if necessary
    if [[ "$filename" == "opkg" ]]; then
        chmod 755 "$destination"
    elif [[ "$filename" == ld-*.so ]]; then
        chmod 755 "$destination"
    fi
done

# Set up dynamic linker and libraries
ln -sf /opt/lib/ld-2.27.so /opt/lib/ld-linux.so.3
ln -sf /opt/lib/libc-2.27.so /opt/lib/libc.so.6

# Install Opkg packages
/opt/bin/opkg update
/opt/bin/opkg install entware-opt wget wget-ssl ca-certificates

echo "Ensuring wget-ssl is used..."
sslPath=""
if [ -f "/opt/bin/wget-ssl" ]; then
    sslPath="/opt/bin/wget-ssl"
elif [ -f "/opt/libexec/wget-ssl" ]; then
    sslPath="/opt/libexec/wget-ssl"
fi

if [ -n "$sslPath" ]; then
    rm -f /opt/bin/wget
    ln -sf "$sslPath" /opt/bin/wget
    echo "Linked $sslPath to /opt/bin/wget."
elif [ -f "/opt/bin/wget" ]; then
    echo "Using existing /opt/bin/wget."
else
    echo "Error: wget-ssl not found."
    EXIT_CODE=1
    cleanup
fi

chmod 777 /opt/tmp

# Create symbolic links for standard files
for file in passwd group shells shadow gshadow localtime; do
    if [ -f "/etc/$file" ]; then
        ln -sf "/etc/$file" "/opt/etc/$file"
    elif [ -f "/opt/etc/${file}.1" ]; then
        cp "/opt/etc/${file}.1" "/opt/etc/$file"
    fi
done

restore_filesystem_state

echo ""
echo "Entware installation successful."
echo "Add /opt/bin and /opt/sbin to PATH? (y/N)"
if [ "$FORCE" = "yes" ]; then
    echo "Force option enabled. Updating PATH..."
    answer="y"
else
    read -r answer </dev/tty
fi

if [ "$answer" = "y" ]; then
    # Create ephemeral system-wide PATH (will be recreated by .profile on next reboot)
    SYSTEM_PROFILE_D="/etc/profile.d"
    ENTWARE_PROFILE="$SYSTEM_PROFILE_D/entware.sh"
    if [ -d "$SYSTEM_PROFILE_D" ] && [ -w "$SYSTEM_PROFILE_D" ]; then
        echo "Creating $ENTWARE_PROFILE to update system-wide PATH."
        echo 'export PATH=/opt/bin:/opt/sbin:$PATH' >"$ENTWARE_PROFILE"
    fi

    # Write persistent profile that survives reboots
    write_persistent_profile

    echo "PATH updated. Please reload your shell or log out and back in for changes to take effect."
else
    echo "Skipping PATH update as per user request."
fi
echo ""
echo "Manage packages using Opkg:"
echo "  opkg update"
echo "  opkg install <package_name>"
echo ""
echo "Installation complete. Thank you for using the RMPP Entware installer."
echo "Happy hacking!"
exit 0
