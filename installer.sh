#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │             ARCH AUTO-INSTALL — GNOME + EFI + GDM               │
# └─────────────────────────────────────────────────────────────────┘

#  Settings ────────────────────────────────────────────────────────
DISK="/dev/sda"
HOSTNAME="archgnome"
USERNAME="karifander"
PASSWORD="230409"
TIMEZONE="Europe/Minsk"
LOCALE="en_US.UTF-8"
KEYMAP="us"
XKB_LAYOUTS="us,ru"
XKB_OPTIONS="grp:alt_shift_toggle"
#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │             ARCH AUTO-INSTALL — GNOME + BIOS + GDM              │
# └─────────────────────────────────────────────────────────────────┘

#  Settings ────────────────────────────────────────────────────────
DISK="/dev/sda"
HOSTNAME="archgnome"
USERNAME="karifander"
PASSWORD="230409"
TIMEZONE="Europe/Minsk"
LOCALE="en_US.UTF-8"
KEYMAP="us"
XKB_LAYOUTS="us,ru"
XKB_OPTIONS="grp:alt_shift_toggle"
SWAP_SIZE="9G"

#  Pre-flight checks ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Run this script as root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "No internet connection"; exit 1; }

# Проверяем BIOS систему
if [[ -d /sys/firmware/efi ]]; then
    echo "ERROR: This is UEFI system, but script is for BIOS!"
    exit 1
fi

#  1) Partitioning ────────────────────────────────────────────────
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
pacstrap /mnt base linux linux-firmware sudo nano networkmanager

#  4) fstab ──────────────────────────────────────────────────────
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

#  5) Configure in chroot ───────────────────────────────────────
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Time zone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Console keymap
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname & hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root password
echo "root:$PASSWORD" | chpasswd

# Create user & grant sudo
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Install desktop environment
pacman -Sy --noconfirm xorg gnome gdm firefox

# Enable NetworkManager
systemctl enable NetworkManager

# Enable GDM
systemctl enable gdm

# Install & configure GRUB (BIOS)
pacman -Sy --noconfirm grub
grub-install --target=i386-pc --recheck "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg

EOF

#  Done ───────────────────────────────────────────────────────────
echo -e "\nInstallation complete! Reboot and enjoy GNOME on Arch."
echo -e "Command: umount -R /mnt && reboot"
