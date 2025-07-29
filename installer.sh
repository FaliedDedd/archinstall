#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │         ARCH INSTALL — FAST KDE + EFI + GDM (AUTOMATIC)        │
# └─────────────────────────────────────────────────────────────────┘

# 💬 Настройки
DISK="/dev/sda"
USER="archuser"
PASS="123123"
HOST="archkde"
LOCALE="en_US.UTF-8"
KEYMAP="ru"
LAYOUT="us,ru"
TOGGLE="grp:alt_shift_toggle"
TIMEZONE="Europe/Minsk"

# 🧠 Проверка
[[ "$EUID" -ne 0 ]] && { echo "🚫 Run as root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "❌ No internet"; exit 1; }

# 🔧 Разметка: EFI, ROOT, SWAP
parted "$DISK" --script mklabel gpt
parted "$DISK" --script mkpart ESP fat32 1MiB 513MiB
parted "$DISK" --script set 1 esp on
parted "$DISK" --script mkpart primary ext4 513MiB 24GiB
parted "$DISK" --script mkpart primary linux-swap 24GiB 100%
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"
mkswap "${DISK}3"
mount "${DISK}2" /mnt
swapon "${DISK}3"
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# 🧱 Базовая система
pacstrap /mnt base base-devel linux linux-firmware vim sudo networkmanager grub efibootmgr xorg

# 📄 fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 🔍 Конфигурация внутри chroot
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# 🗣️ Локаль
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# ⌨️ Консоль
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# 🌐 Время
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# 🖥️ Хост
echo "$HOST" > /etc/hostname
cat >> /etc/hosts <<HOSTS_EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOST.localdomain $HOST
HOSTS_EOF

# 🔐 root пароль
echo "root:$PASS" | chpasswd

# 👤 Пользователь
useradd -m -G wheel,video -s /bin/bash "$USER"
echo "$USER:$PASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# 📡 NetworkManager
systemctl enable NetworkManager

# 🎮 NVIDIA (если есть)
if lspci | grep -i nvidia; then
  pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
  echo "nvidia" > /etc/modules-load.d/nvidia.conf
fi

# 🌐 X11 раскладки
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB_EOF
Section "InputClass"
  Identifier "system-keyboard"
  MatchIsKeyboard "on"
  Option "XkbLayout" "$LAYOUT"
  Option "XkbOptions" "$TOGGLE"
EndSection
XKB_EOF

# 🖼️ Установка KDE + GDM
pacman -Sy --noconfirm plasma kde-applications gdm
systemctl enable gdm

# 🧯 GRUB EFI
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# 🏁 Завершение
echo -e "\n✅ Установка завершена! Перезагрузи и наслаждайся KDE на Arch.\n"
