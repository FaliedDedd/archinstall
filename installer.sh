#!/usr/bin/env bash
set -euo pipefail

# Report errors with line number
trap 'whiptail --backtitle "$BACKTITLE" \
      --msgbox "✖ Error on line $LINENO" 8 60; exit 1' ERR

# ┌─────────────────────────────────────────────────────────┐
# │        ARCH LINUX INSTALLER — SIMPLE EDITION          │
# └─────────────────────────────────────────────────────────┘

clear
tput setaf 2
cat <<"EOF"
   ___  _   _  _  _   _   _  _    _   _  _   ___  
  / _ \| | | || || | | | | || |  | | | || \ |__ \ 
 | | | | |_| || || |_| | | || |_ | | | ||  \   ) |
 | | | |  _  ||__   _| |__   _|| | | || . \ / / 
 | |_| | | | |   | |      | |  | |_| || |\ \_|  
  \___/|_| |_|   |_|      |_|   \___/ |_| \_\(_) 

        Welcome to the Arch Linux Installer
                (no mirrorlist step)
EOF
tput sgr0
sleep 1

BACKTITLE="Arch Installer"

# Step 1: Check Internet
while true; do
  if ping -c1 8.8.8.8 &>/dev/null; then
    whiptail --backtitle "$BACKTITLE" --msgbox \
      "✓ Internet connection detected." 8 60
    break
  else
    whiptail --backtitle "$BACKTITLE" \
      --yesno "✖ No internet connection.\nRetry?" 8 60 || exit 1
  fi
done

# Step 2: Ensure required tools
for tool in whiptail pacstrap genfstab arch-chroot lsblk parted udevadm; do
  if ! command -v "$tool" &>/dev/null; then
    pacman -Sy --noconfirm "$tool" &>/dev/null
  fi
done

# Step 3: Keyboard layout
KEYMAP=$(whiptail --backtitle "$BACKTITLE" --title "Keyboard Layout" \
  --inputbox "Enter layout code (e.g., us, ru):" 10 60 us \
  3>&1 1>&2 2>&3) || exit 1
KEYMAP=${KEYMAP:-us}
if ! loadkeys "$KEYMAP" &>/dev/null; then
  whiptail --backtitle "$BACKTITLE" --msgbox \
    "Cannot load '$KEYMAP'. Falling back to 'us'." 8 60
  loadkeys us &>/dev/null
  KEYMAP=us
fi

# Step 4: Network setup
if whiptail --backtitle "$BACKTITLE" --title "Network" \
     --yesno "Use Wi-Fi? (Yes) or Ethernet? (No)" 8 60; then

  systemctl start iwd &>/dev/null

  WDEV=$(whiptail --backtitle "$BACKTITLE" --title "Wi-Fi Interface" \
    --inputbox "Enter wireless interface name:" 10 60 wlan0 \
    3>&1 1>&2 2>&3) || exit 1

  SSID=$(whiptail --backtitle "$BACKTITLE" --title "SSID" \
    --inputbox "Enter your network SSID:" 10 60 \
    3>&1 1>&2 2>&3) || exit 1

  PSK=$(whiptail --backtitle "$BACKTITLE" --title "Password" \
    --passwordbox "Enter Wi-Fi password for '$SSID':" 10 60 \
    3>&1 1>&2 2>&3) || exit 1

  iwctl station "$WDEV" scan &>/dev/null
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK" &>/dev/null

else
  systemctl start dhcpcd &>/dev/null
fi

# Step 5: Partitioning loop
while true; do
  whiptail --backtitle "$BACKTITLE" --title "Disk Partitioning" \
    --msgbox "Now running cfdisk:\n • Create a root partition\n • (opt.) EFI\n • (opt.) swap\nWrite the changes, then exit." 12 60
  cfdisk

  # Re-read partition table
  for disk in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/" $1}'); do
    partprobe "$disk" || true
  done
  udevadm settle --timeout=5

  # Check if any partitions exist
  if lsblk -pn -o NAME,TYPE | grep -q 'part$'; then
    break
  fi

  # If still no partitions, retry or exit
  if ! whiptail --backtitle "$BACKTITLE" \
       --yesno "No partitions found.\nRe-run cfdisk?" 8 60; then
    exit 1
  fi
done

# Step 6: Partition selector
select_partition() {
  local prompt="$1"
  local opts=()
  while read -r dev type; do
    [[ "$type" == "part" ]] && \
      opts+=( "$dev" "$(lsblk -n -o SIZE "$dev")" )
  done < <(lsblk -pn -o NAME,TYPE)

  [[ ${#opts[@]} -gt 0 ]] || return 1

  whiptail --backtitle "$BACKTITLE" \
    --title "$prompt" \
    --menu "Select partition:" 15 60 6 \
    "${opts[@]}" 3>&1 1>&2 2>&3
}

# Step 7: Format & mount
ROOT=$(select_partition "Root Partition") || exit 1
mkfs.ext4 "$ROOT" &>/dev/null
mount "$ROOT" /mnt

EFI=$(select_partition "EFI Partition (optional)") || true
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI" &>/dev/null
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

SWAP=$(select_partition "Swap Partition (optional)") || true
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP" &>/dev/null
  swapon "$SWAP"
fi

# Step 8: Install base system
whiptail --backtitle "$BACKTITLE" --title "Installing Base" \
  --gauge "Running pacstrap..." 6 60 0
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed &>/dev/null

# Step 9: Generate fstab
whiptail --backtitle "$BACKTITLE" --title "fstab" \
  --msgbox "Generating fstab file…" 6 60
genfstab -U /mnt >> /mnt/etc/fstab

# Step 10: Chroot & configure
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap 'whiptail --msgbox "✖ Chroot error on line $LINENO" 8 60; exit 1' ERR

BACKTITLE="Chroot Setup"

# Locale
LOCALE=$(whiptail --backtitle "$BACKTITLE" --title "Locale" \
  --inputbox "Enter locale (e.g., en_US.UTF-8):" 10 60 en_US.UTF-8 \
  3>&1 1>&2 2>&3) || exit 1
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=$LOCALE" > /etc/locale.conf

# Time zone
TZ=$(whiptail --backtitle "$BACKTITLE" --title "Time Zone" \
  --inputbox "Enter time zone (e.g., Europe/Minsk):" 10 60 Europe/Minsk \
  3>&1 1>&2 2>&3) || exit 1
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
hwclock --systohc &>/dev/null

# Hostname
HOSTNAME=$(whiptail --backtitle "$BACKTITLE" --title "Hostname" \
  --inputbox "Enter hostname:" 10 60 archlinux \
  3>&1 1>&2 2>&3) || exit 1
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<EOD
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOD

# Root password
PASS_ROOT=$(whiptail --backtitle "$BACKTITLE" --title "Root Password" \
  --passwordbox "Set root password:" 10 60 \
  3>&1 1>&2 2>&3) || exit 1
echo "root:$PASS_ROOT" | chpasswd

# Add a non-root user
if whiptail --backtitle "$BACKTITLE" --title "Add User" \
     --yesno "Create a non-root user?" 10 60; then

  USER=$(whiptail --backtitle "$BACKTITLE" --title "Username" \
    --inputbox "Enter username:" 10 60 user \
    3>&1 1>&2 2>&3) || exit 1
  useradd -m -G wheel,storage,power -s /bin/bash "$USER"

  PASS_USER=$(whiptail --backtitle "$BACKTITLE" --title "User Password" \
    --passwordbox "Set password for $USER:" 10 60 \
    3>&1 1>&2 2>&3) || exit 1
  echo "$USER:$PASS_USER" | chpasswd

  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

# Install and configure GRUB
if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr &>/dev/null
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub &>/dev/null
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

# Step 11: Finish
whiptail --backtitle "$BACKTITLE" --title "Done!" \
  --msgbox "Installation complete!\nPlease reboot and remove installation media." 8 60

exit 0
```
