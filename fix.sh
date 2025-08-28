#!/bin/bash

# Простая установка Arch Linux с GNOME
set -e

# Настройки
DISK="/dev/sda"
USER="user"
PASS="123456"
HOST="arch"

# Разметка диска
echo "Создание разделов..."
parted -s $DISK mklabel msdos
parted -s $DISK mkpart primary ext4 1MiB 90%
parted -s $DISK mkpart primary linux-swap 90% 100%
parted -s $DISK set 1 boot on

# Форматирование
echo "Форматирование..."
mkfs.ext4 ${DISK}1
mkswap ${DISK}2
swapon ${DISK}2

# Монтирование
mount ${DISK}1 /mnt

# Установка системы
echo "Установка Arch Linux..."
pacstrap /mnt base linux linux-firmware

# Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Настройка системы
arch-chroot /mnt /bin/bash <<EOF

# Время
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# Локализация
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Клавиатура
echo "KEYMAP=us" > /etc/vconsole.conf

# Хостнейм
echo "$HOST" > /etc/hostname

# Пароли
echo "root:$PASS" | chpasswd
useradd -m -G wheel -s /bin/bash $USER
echo "$USER:$PASS" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Графика
pacman -Sy --noconfirm xorg gnome gdm
systemctl enable gdm
systemctl enable NetworkManager

# Загрузчик
pacman -Sy --noconfirm grub
grub-install --target=i386-pc --recheck $DISK
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Завершение
echo "Установка завершена!"
echo "Перезагрузитесь: umount -R /mnt && reboot"
