#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │             ARCH AUTO-INSTALL — KDE + EFI + GDM               │
# └─────────────────────────────────────────────────────────────────┘

#  Settings ────────────────────────────────────────────────────────
DISK="/dev/nvme1n1"
HOSTNAME="archkde"
USERNAME="archuser"
PASSWORD="archlinux"
TIMEZONE="Europe/Minsk"
LOCALE="en_US.UTF-8"
KEYMAP="ru"
XKB_LAYOUTS="us,ru"
XKB_OPTIONS="grp:alt_shift_toggle"
EFI_SIZE="512MiB"
SWAP_SIZE="1GiB"

#  Pre-flight checks ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Run this script as root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "No internet connection"; exit 1; }

#  1) Partitioning ────────────────────────────────────────────────
parted "$DISK" --script mklabel gpt
parted "$DISK" --script mkpart ESP fat32 1MiB $EFI_SIZE
parted "$DISK" --script set 1 esp on
parted "$DISK" --script mkpart primary ext4 $EFI_SIZE "-$SWAP_SIZE"
parted "$DISK" --script mkpart primary linux-swap "-$SWAP_SIZE" 100%

#  2) Format & mount ─────────────────────────────────────────────
mkfs.fat -F32 "${DISK}p1"
mkfs.ext4   "${DISK}p2"
mkswap      "${DISK}p3"
mount       "${DISK}p2" /mnt
swapon      "${DISK}p3"
mkdir -p    /mnt/boot
mount       "${DISK}p1" /mnt/boot

#  3) Base system install ────────────────────────────────────────
pacstrap /mnt \
  base linux linux-firmware sudo nano vim networkmanager \
  grub efibootmgr xorg plasma kde-applications gdm

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

# NVIDIA setup (if present)
if lspci | grep -i nvidia &>/dev/null; then
  pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
  echo "nvidia" > /etc/modules-load.d/nvidia.conf
  mkinitcpio -p linux
fi

# Install & configure GRUB (UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

#  Done ───────────────────────────────────────────────────────────
echo -e "\nInstallation complete! Reboot and enjoy KDE with GDM on Arch.\n"
```
