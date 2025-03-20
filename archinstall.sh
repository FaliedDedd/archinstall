#!/bin/bash




DISK="/dev/nvme0n1"

BOOT_PART="${DISK}p1"

ROOT_PART="${DISK}p2"


USERNAME="falied"



if [[ $EUID -ne 0 ]]; then

   echo "Please start this script with root perm."

@@ -21,24 +21,24 @@

mkdir -p /mnt/boot

mount $BOOT_PART /mnt/boot




pacstrap /mnt base linux linux-firmware sudo grub efibootmgr gnome gdm base-devel nano vim networkmanager git xorg ttf-ubuntu-font-family



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

passwd

echo "$USERNAME:password" | chpasswd

echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

grub-mkconfig -o /boot/grub/grub.cfg

EOF



echo "Install complete. Please settings sudoers and create passwd -m username"
