#!/usr/bin/env bash
set -euo pipefail
trap 'whiptail --msgbox "✖ Error on line $LINENO" 8 40; exit 1' ERR

# ┌───────────────────────────────────────────────┐
# │      ARCH LINUX INSTALLER — BELARUS & EU      │
# └───────────────────────────────────────────────┘

clear
tput setaf 2
cat <<"EOF"


     Welcome to the Arch Linux Installer
     I'm not gay
     (Belarus first, Europe as fallback)
EOF
tput sgr0
sleep 1

BACKTITLE="Arch Installer — BY→EU"

# Step 1: Internet connectivity check
while true; do
  if ping -c1 8.8.8.8 &>/dev/null; then
    whiptail --backtitle "$BACKTITLE" --msgbox \
      "✓ Internet connection detected." 8 50
    break
  else
    whiptail --backtitle "$BACKTITLE" --yesno \
      "✖ No internet connection.\nRetry?" 8 50 || exit 1
  fi
done

# Step 2: Ensure helper tools
TOOLS=(whiptail reflector pacstrap genfstab arch-chroot)
for t in "${TOOLS[@]}"; do
  if ! command -v "$t" &>/dev/null; then
    pacman -Sy --noconfirm "$t" &>/dev/null
  fi
done

# Step 3: Keyboard layout
KEYMAP=$(whiptail --backtitle "$BACKTITLE" --title "Keyboard Layout" \
  --inputbox "Enter layout code (us, ru, etc.):" 10 50 us \
  3>&1 1>&2 2>&3) || exit 1
KEYMAP=${KEYMAP:-us}
if ! loadkeys "$KEYMAP" &>/dev/null; then
  loadkeys us &>/dev/null
  KEYMAP=us
fi

# Step 4: Mirrorlist BY→EU
whiptail --backtitle "$BACKTITLE" --title "Updating Mirrorlist" \
  --gauge "Fetching fastest HTTPS mirrors for Belarus..." 6 50 10
reflector --country "Belarus" --age 12 --protocol https \
  --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null

if ! grep -q '^Server' /etc/pacman.d/mirrorlist; then
  whiptail --backtitle "$BACKTITLE" --title "Fallback" \
    --gauge "No Belarus mirrors found. Falling back to Europe..." 6 50 10
  reflector --continent Europe --age 12 --protocol https \
    --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null
fi

sleep 1

# Step 5: Network setup
if whiptail --backtitle "$BACKTITLE" --title "Network Setup" \
     --yesno "Use Wi-Fi? (Yes) or Ethernet (No)" 8 50; then

  systemctl start iwd &>/dev/null
  WDEV=$(whiptail --backtitle "$BACKTITLE" --title "Wi-Fi Device" \
    --inputbox "Enter your Wi-Fi interface (e.g., wlan0):" 10 50 wlan0 \
    3>&1 1>&2 2>&3) || exit 1

  SSID=$(whiptail --backtitle "$BACKTITLE" --title "SSID" \
    --inputbox "Enter Wi-Fi network name:" 10 50 \
    3>&1 1>&2 2>&3) || exit 1

  PSK=$(whiptail --backtitle "$BACKTITLE" --title "Password" \
    --passwordbox "Enter password for $SSID:" 10 50 \
    3>&1 1>&2 2>&3) || exit 1

  iwctl station "$WDEV" scan &>/dev/null
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK" &>/dev/null

else
  systemctl start dhcpcd &>/dev/null
fi

# Step 6: Disk partitioning
whiptail --backtitle "$BACKTITLE" --title "Disk Partitioning" \
  --msgbox "cfdisk will open. Create:\n • root\n • (opt) EFI\n • (opt) swap\nSave and exit." 10 50
cfdisk

# Step 7: Format & mount
ROOT=$(whiptail --backtitle "$BACKTITLE" --title "Root Partition" \
  --inputbox "Root partition (e.g., /dev/sda1):" 10 50 \
  3>&1 1>&2 2>&3) || exit 1
mkfs.ext4 "$ROOT" &>/dev/null
mount "$ROOT" /mnt

EFI=$(whiptail --backtitle "$BACKTITLE" --title "EFI Partition" \
  --inputbox "EFI partition (leave empty if none):" 10 50 \
  3>&1 1>&2 2>&3) || exit 1
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI" &>/dev/null
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

SWAP=$(whiptail --backtitle "$BACKTITLE" --title "Swap Partition" \
  --inputbox "Swap partition (leave empty if none):" 10 50 \
  3>&1 1>&2 2>&3) || exit 1
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP" &>/dev/null
  swapon "$SWAP"
fi

# Step 8: Install base system
whiptail --backtitle "$BACKTITLE" --title "Installing Base System" \
  --gauge "Running pacstrap..." 6 50 10
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed &>/dev/null

# Step 9: Generate fstab
whiptail --backtitle "$BACKTITLE" --title "Generating fstab" \
  --msgbox "Creating fstab…" 6 50
genfstab -U /mnt >> /mnt/etc/fstab

# Step 10: Chroot configuration
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap 'whiptail --msgbox "✖ Chroot error on line $LINENO" 8 40; exit 1' ERR

BACKTITLE="Arch Installer — Chroot"

# Locale
LOCALE=$(whiptail --backtitle "$BACKTITLE" --title "Locale" \
  --inputbox "Enter locale (e.g., en_US.UTF-8 ru_RU.UTF-8):" 10 50 en_US.UTF-8 \
  3>&1 1>&2 2>&3) || exit 1
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=$LOCALE" > /etc/locale.conf

# Time zone
TZ=$(whiptail --backtitle "$BACKTITLE" --title "Time Zone" \
  --inputbox "Enter time zone (e.g., Europe/Minsk):" 10 50 Europe/Minsk \
  3>&1 1>&2 2>&3) || exit 1
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
hwclock --systohc &>/dev/null

# Hostname
HOSTNAME=$(whiptail --backtitle "$BACKTITLE" --title "Hostname" \
  --inputbox "Enter hostname:" 10 50 archlinux \
  3>&1 1>&2 2>&3) || exit 1
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<EOD
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOD

# Root password
PASS_ROOT=$(whiptail --backtitle "$BACKTITLE" --title "Root Password" \
  --passwordbox "Set root password:" 10 50 \
  3>&1 1>&2 2>&3) || exit 1
echo "root:$PASS_ROOT" | chpasswd

# Create user
if whiptail --backtitle "$BACKTITLE" --title "Add User" \
     --yesno "Create a non-root user?" 10 50; then

  USER=$(whiptail --backtitle "$BACKTITLE" --title "Username" \
    --inputbox "Enter username:" 10 50 user \
    3>&1 1>&2 2>&3) || exit 1
  useradd -m -G wheel,storage,power -s /bin/bash "$USER"

  PASS_USER=$(whiptail --backtitle "$BACKTITLE" --title "User Password" \
    --passwordbox "Set password for $USER:" 10 50 \
    3>&1 1>&2 2>&3) || exit 1
  echo "$USER:$PASS_USER" | chpasswd

  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

# Install GRUB
if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr &>/dev/null
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub &>/dev/null
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

# Finish
whiptail --backtitle "$BACKTITLE" --title "Done!" \
  --msgbox "Installation complete!\nReboot and remove the installation media." 10 50

exit 0
