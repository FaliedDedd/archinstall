#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │             ARCH AUTO-INSTALL — GNOME + BIOS + GDM              │
# └─────────────────────────────────────────────────────────────────┘

#  Settings ────────────────────────────────────────────────────────
DISK="/dev/sda"
HOSTNAME="archgnome"
USERNAME="f"
PASSWORD="10"
TIMEZONE="Europe/Minsk"
LOCALE="en_US.UTF-8"
KEYMAP="us"
XKB_LAYOUTS="us,ru"
XKB_OPTIONS="grp:alt_shift_toggle"
SWAP_SIZE="9G"

#  Pre-flight checks ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Run this script as root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "No internet connection"; exit 1; }

# Проверяем, что это BIOS система
if [[ -d /sys/firmware/efi ]]; then
    echo "ERROR: This system uses UEFI, but script is configured for BIOS!"
    echo "Please use the UEFI version of the script."
    exit 1
fi

#  1) Partitioning ────────────────────────────────────────────────
# Wipe existing partitions, create MBR and two partitions: root and swap
echo "Creating MBR partition table..."
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB -${SWAP_SIZE}
parted -s "$DISK" mkpart primary linux-swap -${SWAP_SIZE} 100%
parted -s "$DISK" set 1 boot on
partprobe "$DISK"

#  2) Format & mount ─────────────────────────────────────────────
echo "Formatting partitions..."
mkfs.ext4 "${DISK}1"
mkswap    "${DISK}2"
swapon    "${DISK}2"

mount     "${DISK}1" /mnt

#  3) Base system install ────────────────────────────────────────
echo "Installing base system..."
pacstrap /mnt \
  base linux linux-firmware sudo nano vim networkmanager \
  xorg gnome gnome-extra firefox grub gdm

#  4) fstab ──────────────────────────────────────────────────────
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

#  5) Configure in chroot ───────────────────────────────────────
echo "Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Time zone
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "Configuring locale..."
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Console keymap
echo "Setting keymap..."
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname & hosts
echo "Setting hostname..."
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root password
echo "Setting root password..."
echo "root:$PASSWORD" | chpasswd

# Create user & grant sudo
echo "Creating user..."
useradd -m -G wheel,video,audio,storage,network -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable NetworkManager
echo "Enabling NetworkManager..."
systemctl enable NetworkManager

# X11 keyboard layouts
echo "Configuring X11 keyboard..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB
Section "InputClass"
  Identifier "system-keyboard"
  MatchIsKeyboard "on"
  Option "XkbLayout" "$XKB_LAYOUTS"
  Option "XkbOptions" "$XKB_OPTIONS"
EndSection
XKB

# Enable GDM
echo "Enabling GDM..."
systemctl enable gdm

# NVIDIA setup (if present)
if lspci | grep -i nvidia &>/dev/null; then
  echo "Installing NVIDIA drivers..."
  pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
  echo "nvidia" > /etc/modules-load.d/nvidia.conf
  mkinitcpio -P
fi

# Install & configure GRUB (BIOS)
echo "Installing GRUB for BIOS..."
grub-install --target=i386-pc --recheck "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg

EOF

#  Done ───────────────────────────────────────────────────────────
echo -e "\nInstallation complete! Reboot and enjoy GNOME on Arch."
echo -e "Don't forget to remove installation media before rebooting!\n"
