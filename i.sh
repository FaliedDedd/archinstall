#!/bin/bash
echo "Enter your disk (e.g., sda or nvme0n1 without /dev/):"
read disk

DISK="/dev/$disk"
BOOT_PART="${DISK}p1"
SWAP_PART="${DISK}p2"
ROOT_PART="${DISK}p3"
USERNAME="falied"

if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root."
   exit 1
fi

sgdisk --zap-all $DISK
sgdisk -n 1:0:+2G -t 1:ef00 -c 1:"EFI Boot" $DISK
sgdisk -n 2:0:+20G -t 2:8200 -c 2:"Linux Swap" $DISK
sgdisk -n 3:0:0 -t 3:8300 -c 3:"Linux Root" $DISK

mkfs.fat -F32 $BOOT_PART
mkswap $SWAP_PART
mkfs.ext4 $ROOT_PART

swapon $SWAP_PART
mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $BOOT_PART /mnt/boot

pacstrap /mnt base linux linux-firmware sudo grub efibootmgr \
         cinnamon gdm base-devel nano vim networkmanager git \
         xorg ttf-ubuntu-font-family

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Minsk /etc/localtime
hwclock --systohc
systemctl enable gdm
systemctl enable NetworkManager
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
useradd -m -G wheel -s /bin/bash $USERNAME
echo "Set a password for user $USERNAME"
passwd $USERNAME
echo "$USERNAME:password" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete. Please check sudoers and set a secure password for user $USERNAME."
