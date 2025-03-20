#!/bin/bash
echo "Check disk partition"
echo "Write your disk"


DISK="/dev/sda"
BOOT_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
USERNAME="falied"

if [[ $EUID -ne 0 ]]; then
   echo "Please start this script with root perm."
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

pacstrap /mnt base linux linux-firmware sudo grub efibootmgr gnome gdm base-devel nano vim networkmanager git xorg ttf-ubuntu-font-family nvidia nvidia-utils xf86-video-amdgpu

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


mkdir -p /etc/X11/xorg.conf.d
cat <<EOL > /etc/X11/xorg.conf.d/10-nvidia.conf
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration" "true"
EndSection
EOL


cat <<EOL > /etc/X11/xorg.conf.d/20-amd.conf
Section "Device"
    Identifier "AMD Card"
    Driver "amdgpu"
EndSection
EOL


pacman -S --noconfirm nvidia-prime

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Install complete. Please settings sudoers and create passwd -m username"
