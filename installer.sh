#!/usr/bin/env bash
set -euo pipefail

# === Настройки ===
USERNAME="archuser"
PASSWORD="archlinux"
DISK="/dev/sda"
HOSTNAME="archlinux"
LOCALE="en_US.UTF-8"
KEYMAP="ru"
TIMEZONE="Europe/Minsk"
BACKTITLE="Arch KDE Auto Installer"

# === Проверка ===
[[ $EUID -ne 0 ]] && { echo "❌ Скрипт нужно запускать от root"; exit 1; }
ping -c1 archlinux.org &>/dev/null || { echo "❌ Нет подключения к интернету"; exit 1; }

# === Разметка диска (/dev/sda: ~24ГБ + 1ГБ swap) ===
parted "$DISK" --script mklabel msdos
parted "$DISK" --script mkpart primary ext4 1MiB 24GiB
parted "$DISK" --script mkpart primary linux-swap 24GiB 100%
mkfs.ext4 "${DISK}1"
mkswap "${DISK}2"
swapon "${DISK}2"
mount "${DISK}1" /mnt

# === Установка системы ===
pacstrap /mnt base base-devel linux linux-firmware sudo vim nano git networkmanager grub xorg

# === fstab ===
genfstab -U /mnt >> /mnt/etc/fstab

# === Конфигурация в chroot ===
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Локаль
echo "$LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Часовой пояс
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Имя хоста
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS_EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Клавиатура в консоли
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# root пароль
echo "root:$PASSWORD" | chpasswd

# Создание пользователя
useradd -m -G wheel,video,network -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# === Язык и раскладки в X11 ===
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB_EOF
Section "InputClass"
  Identifier "system-keyboard"
  MatchIsKeyboard "on"
  Option "XkbLayout" "us,ru"
  Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
XKB_EOF

# === Wi-Fi ===
systemctl enable NetworkManager

# === KDE Plasma + GUI ===
pacman -Sy --noconfirm plasma kde-applications sddm konsole dolphin ark
systemctl enable sddm

# === NVIDIA ===
if lspci | grep -i nvidia; then
  pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings
  echo "nvidia" > /etc/modules-load.d/nvidia.conf
fi

# === Bootloader ===
grub-install --target=i386-pc "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# === Завершение ===
echo "✅ Установка завершена. Перезагрузись и наслаждайся!"
