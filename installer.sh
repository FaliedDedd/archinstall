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
EFI_SIZE="2G"
SWAP_SIZE="9G"

#  Pre-flight checks ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Run this script as root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "No internet connection"; exit 1; }

#  1) Partitioning ────────────────────────────────────────────────
# Wipe existing partitions, create GPT and three partitions: EFI, root, swap
sgdisk --zap-all "$DISK"
sgdisk --new=1:1M:+${EFI_SIZE}    --typecode=1:ef00 --change-name=1:'EFI System'  "$DISK"
sgdisk --new=2:0:-${SWAP_SIZE}    --typecode=2:8300 --change-name=2:'Linux root'   "$DISK"
sgdisk --new=3:-${SWAP_SIZE}:0    --typecode=3:8200 --change-name=3:'Linux swap'   "$DISK"
partprobe "$DISK"

#  2) Format & mount ─────────────────────────────────────────────
mkfs.fat -F32 "${DISK}1"
mkfs.ext4   "${DISK}2"
mkswap      "${DISK}3"
swapon      "${DISK}3"

mount       "${DISK}2" /mnt
mkdir -p    /mnt/boot
mount       "${DISK}1" /mnt/boot

#  3) Base system install ────────────────────────────────────────
pacstrap /mnt \
  base linux linux-firmware sudo nano vim networkmanager \
  xorg gnome gnome-extra firefox grub efibootmgr gdm

#  4) fstab ──────────────────────────────────────────────────────
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
cat >> /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root password
echo "root:$PASSWORD" | chpasswd

# Create user & grant sudo
useradd -m -G wheel,video,audio,storage,network -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable NetworkManager
systemctl enable NetworkManager

# X11 keyboard layouts
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
systemctl enable gdm



# Install & configure GRUB (UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

#  Done ───────────────────────────────────────────────────────────
echo -e "\nInstallation complete! Reboot and enjoy GNOME on Arch.\n"
