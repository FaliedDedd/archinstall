#!/bin/bash

echo "Please write disk name (например, /dev/sdX):"
lsblk
read -p "Select disk: " disk

DISK="/dev/$disk"
BOOT_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

read -p "Write username: " USERNAME
read -s -p "Write password: " PASSWORD
echo

if [[ $EUID -ne 0 ]]; then
   echo "Пожалуйста, запустите этот скрипт с root-правами."
   exit 1
fi

sgdisk --zap-all $DISK
sgdisk -n 1:0:+2G -t 1:ef00 -c 1:"EFI Boot" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux Root" $DISK

mkfs.fat -F32 $BOOT_PART
mkfs.ext4 $ROOT_PART

mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $BOOT_PART /mnt/boot

pacstrap /mnt base linux linux-firmware sudo grub efibootmgr gnome gdm base-devel nano vim networkmanager git xorg ttf-ubuntu-font-family nvidia nvidia-utils nvidia-settings

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/Europe/Minsk /etc/localtime
hwclock --systohc

systemctl enable gdm
systemctl enable NetworkManager

echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "options nvidia-drm modeset=1" >> /etc/modprobe.d/nvidia.conf
mkinitcpio -P

EOF

echo "Установка завершена! Пользователь $USERNAME создан, настройки sudo установлены, root-пароль установлен, драйверы NVIDIA настроены."
