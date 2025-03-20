#!/bin/bash
echo "Check disk partition"
echo "Available disks:"
lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
echo "Please write your disk name (e.g., nvme0n1 or sda):"
read disk
echo "What is your name?"
read user


if [ ! -b "/dev/$disk" ]; then
    echo "Disk /dev/$disk does not exist. Please check the name and try again."
    exit 1
fi

lsblk
echo "Using disk: /dev/$disk"
DISK="/dev/$disk"
BOOT_PART="${DISK}p1"
ROOT_PART="${DISK}p2"
USERNAME="$user"

if [[ $EUID -ne 0 ]]; then
   echo "Please start this script with root permissions."
   exit 1
fi


sgdisk --zap-all $DISK
if [ $? -ne 0 ]; then
    echo "Failed to zap the disk. Please check if the disk is in use."
    exit 1
fi


sgdisk -n 1:0:+2G -t 1:ef00 -c 1:"EFI Boot" $DISK
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux Root" $DISK
if [ $? -ne 0 ]; then
    echo "Failed to create partitions."
    exit 1
fi


mkfs.fat -F32 $BOOT_PART
mkfs.ext4 $ROOT_PART


mount $ROOT_PART /mnt
if [ $? -ne 0 ]; then
    echo "Failed to mount root partition."
    exit 1
fi

mkdir -p /mnt/boot
mount $BOOT_PART /mnt/boot
if [ $? -ne 0 ]; then
    echo "Failed to mount boot partition."
    exit 1
fi


pacstrap /mnt base linux linux-firmware sudo grub efibootmgr cinnamon gdm base-devel nano vim networkmanager git xorg ttf-ubuntu-font-family nvidia nvidia-utils xf86-video-amdgpu


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


echo "Set password for user $USERNAME:"
passwd $USERNAME


echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers


read -p "Do you want to add NVIDIA configuration? (y/n): " add_nvidia
if [[ $add_nvidia == "y" || $add_nvidia == "Y" ]]; then
    mkdir -p /etc/X11/xorg.conf.d
    cat <<EOL > /etc/X11/xorg.conf.d/10-nvidia.conf
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration" "true"
EndSection
EOL
    echo "NVIDIA configuration added."
fi

read -p "Do you want to add AMD configuration? (y/n): " add_amd
if [[ $add_amd == "y" || $add_amd == "Y" ]]; then
    mkdir -p /etc/X11/xorg.conf.d
    cat <<EOL > /etc/X11/xorg.conf.d/20-amd.conf
Section "Device"
    Identifier "AMD Card"
    Driver "amdgpu"
EndSection
EOL
    echo "AMD configuration added."
fi

pacman -S --noconfirm n
