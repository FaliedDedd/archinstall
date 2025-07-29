#!/usr/bin/env bash
set -euo pipefail
trap 'echo "✖ Error on line $LINENO"; exit 1' ERR

# ┌─────────────────────────────────────────────────────────┐
# │           ARCH LINUX INSTALLER — BELARUS              │
# └─────────────────────────────────────────────────────────┘

# Colored ASCII‐art header
clear
tput setaf 2
cat <<"EOF"

      Welcome to the Arch Linux Installer
                     for Belarus
EOF
tput sgr0
sleep 2

BACKTITLE="Arch Linux Installer — Belarus"

# 0️⃣ Check for and install helper tools if missing
required=(whiptail reflector pacstrap genfstab arch-chroot)
for cmd in "${required[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    whiptail --backtitle "$BACKTITLE" \
      --msgbox "Installing missing tool: $cmd" 8 60
    pacman -Sy --noconfirm "$cmd"
  fi
done

# 1️⃣ Keyboard layout
KEYMAP=$(whiptail --backtitle "$BACKTITLE" \
  --title "Keyboard Layout" \
  --inputbox "Enter your keyboard layout code (e.g., us, ru):" 10 60 us \
  3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
  echo "╳ Setup cancelled by user."; exit 1
fi
KEYMAP=${KEYMAP:-us}

if ! loadkeys "$KEYMAP"; then
  whiptail --backtitle "$BACKTITLE" \
    --msgbox "Failed to load '$KEYMAP'. Falling back to 'us'." 8 60
  loadkeys us
  KEYMAP=us
fi

# 2️⃣ Mirrorlist for Belarus
whiptail --backtitle "$BACKTITLE" \
  --title "Updating Mirrorlist" \
  --msgbox "Configuring pacman mirrors for Belarus region..." 8 60

reflector \
  --country "Belarus" \
  --age 12 \
  --protocol https \
  --sort rate \
  --save /etc/pacman.d/mirrorlist

# 3️⃣ Network configuration
if whiptail --backtitle "$BACKTITLE" \
     --title "Network Setup" \
     --yesno "Do you need to configure Wi-Fi?\nSelect Yes for Wi-Fi, No for Ethernet." 10 60; then

  whiptail --backtitle "$BACKTITLE" \
    --msgbox "We will use iwd to connect to your Wi-Fi network." 8 60

  systemctl start iwd

  WDEV=$(whiptail --backtitle "$BACKTITLE" \
    --title "Wi-Fi Device" \
    --inputbox "Enter your Wi-Fi device name (e.g., wlan0):" 10 60 wlan0 \
    3>&1 1>&2 2>&3)
  SSID=$(whiptail --backtitle "$BACKTITLE" \
    --title "SSID" \
    --inputbox "Enter the SSID of your network:" 10 60 \
    3>&1 1>&2 2>&3)
  PSK=$(whiptail --backtitle "$BACKTITLE" \
    --title "Password" \
    --passwordbox "Enter the password for '$SSID':" 10 60 \
    3>&1 1>&2 2>&3)

  iwctl station "$WDEV" scan
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK"

else
  whiptail --backtitle "$BACKTITLE" \
    --msgbox "Starting DHCP client for Ethernet..." 8 60
  systemctl start dhcpcd
fi

# 4️⃣ Disk partitioning (manual)
whiptail --backtitle "$BACKTITLE" \
  --title "Disk Partitioning" \
  --msgbox "cfdisk will open. Create at least:\n  • root partition\n  • (optional) EFI partition\n  • (optional) swap\nThen write changes and exit." 12 60
cfdisk

# 5️⃣ Format & mount
ROOT=$(whiptail --backtitle "$BACKTITLE" \
  --title "Root Partition" \
  --inputbox "Specify your root partition (e.g., /dev/sda1):" 10 60 \
  3>&1 1>&2 2>&3)
[[ -n "$ROOT" ]] || { echo "╳ Root partition not specified."; exit 1; }
mkfs.ext4 "$ROOT"
mount "$ROOT" /mnt

EFI=$(whiptail --backtitle "$BACKTITLE" \
  --title "EFI Partition" \
  --inputbox "Specify your EFI partition (leave empty if none):" 10 60 \
  3>&1 1>&2 2>&3)
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI"
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

SWAP=$(whiptail --backtitle "$BACKTITLE" \
  --title "Swap Partition" \
  --inputbox "Specify your swap partition (leave empty if none):" 10 60 \
  3>&1 1>&2 2>&3)
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP"
  swapon "$SWAP"
fi

# 6️⃣ Install base system
whiptail --backtitle "$BACKTITLE" \
  --title "Pacstrap" \
  --msgbox "Installing base packages..." 8 60
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed

# 7️⃣ Generate fstab
whiptail --backtitle "$BACKTITLE" \
  --title "Generating fstab" \
  --msgbox "Creating /etc/fstab…" 8 60
genfstab -U /mnt >> /mnt/etc/fstab

# 8️⃣ Chroot configuration
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap 'echo "✖ Error in chroot on line $LINENO"; exit 1' ERR

# Backtitle inside chroot
BACKTITLE="Arch Linux Installer — Chroot"

# 8.1 Locale
LOCALE=$(whiptail --backtitle "$BACKTITLE" \
  --title "Locale" \
  --inputbox "Enter your locale (e.g., en_US.UTF-8 ru_RU.UTF-8):" 10 60 \
  en_US.UTF-8 3>&1 1>&2 2>&3)
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# 8.2 Time zone
TZ=$(whiptail --backtitle "$BACKTITLE" \
  --title "Time Zone" \
  --inputbox "Enter your time zone (e.g., Europe/Minsk):" 10 60 \
  Europe/Minsk 3>&1 1>&2 2>&3)
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
hwclock --systohc

# 8.3 Hostname & hosts
HOSTNAME=$(whiptail --backtitle "$BACKTITLE" \
  --title "Hostname" \
  --inputbox "Enter the hostname for this machine:" 10 60 \
  archlinux 3>&1 1>&2 2>&3)
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<EOD
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOD

# 8.4 Root password
PASS_ROOT=$(whiptail --backtitle "$BACKTITLE" \
  --title "Root Password" \
  --passwordbox "Set the root password:" 10 60 \
  3>&1 1>&2 2>&3)
echo "root:$PASS_ROOT" | chpasswd

# 8.5 Create a new user
if whiptail --backtitle "$BACKTITLE" \
     --title "Add User" \
     --yesno "Would you like to create a new user?" 10 60; then

  USERNAME=$(whiptail --backtitle "$BACKTITLE" \
    --title "Username" \
    --inputbox "Enter a username:" 10 60 user \
    3>&1 1>&2 2>&3)
  useradd -m -G wheel,storage,power -s /bin/bash "$USERNAME"

  PASS_USER=$(whiptail --backtitle "$BACKTITLE" \
    --title "User Password" \
    --passwordbox "Set password for $USERNAME:" 10 60 \
    3>&1 1>&2 2>&3)
  echo "$USERNAME:$PASS_USER" | chpasswd

  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

# 8.6 Install GRUB
if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# 🎉 Finished
whiptail --backtitle "$BACKTITLE" \
  --title "Done!" \
  --msgbox "Installation complete!\nReboot and remove the installation media." 10 60

exit 0
```
