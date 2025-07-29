#!/usr/bin/env bash
set -euo pipefail

BACKTITLE="Arch Installer"
# Enhanced trap to show line and command on error
trap '
  echo >&2 "✖ Error on line $LINENO: ${BASH_COMMAND}"
  whiptail --backtitle "$BACKTITLE" \
    --msgbox "✖ Error on line $LINENO\n${BASH_COMMAND}" 10 70
  exit 1
' ERR

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
                (manual partition entry)
EOF
tput sgr0
sleep 1

# 1) Check Internet
while ! ping -c1 8.8.8.8 &>/dev/null; do
  whiptail --backtitle "$BACKTITLE" \
    --yesno "No internet connection.\nRetry?" 8 60 || exit 1
done
whiptail --backtitle "$BACKTITLE" --msgbox "✓ Internet OK" 8 60

# 2) Ensure tools
for t in whiptail pacstrap genfstab arch-chroot lsblk partprobe udevadm; do
  if ! command -v "$t" &>/dev/null; then
    pacman -Sy --noconfirm "$t" &>/dev/null
  fi
done

# 3) Keymap
KEYMAP=$(whiptail --backtitle "$BACKTITLE" --title "Keyboard Layout" \
  --inputbox "Layout code (us, ru):" 10 50 us \
  3>&1 1>&2 2>&3) || exit 1
KEYMAP=${KEYMAP:-us}
loadkeys "$KEYMAP" &>/dev/null || loadkeys us &>/dev/null

# 4) Network: Wi-Fi or Ethernet
if whiptail --backtitle "$BACKTITLE" --title "Network" \
     --yesno "Use Wi-Fi? Yes: Wi-Fi, No: Ethernet" 8 60; then
  systemctl start iwd &>/dev/null
  WDEV=$(whiptail --backtitle "$BACKTITLE" --inputbox \
    "Wi-Fi interface (e.g. wlan0):" 10 50 wlan0 \
    3>&1 1>&2 2>&3) || exit 1
  SSID=$(whiptail --backtitle "$BACKTITLE" --inputbox \
    "SSID:" 10 50 \
    3>&1 1>&2 2>&3) || exit 1
  PSK=$(whiptail --backtitle "$BACKTITLE" --passwordbox \
    "Password for $SSID:" 10 50 \
    3>&1 1>&2 2>&3) || exit 1
  iwctl station "$WDEV" scan &>/dev/null
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK" &>/dev/null
else
  systemctl start dhcpcd &>/dev/null
fi

# 5) Partitioning loop
while true; do
  whiptail --backtitle "$BACKTITLE" --title "Partitioning" \
    --msgbox "cfdisk will run.\nCreate at least root, optionally EFI and swap.\nSave and exit." 12 60
  cfdisk

  # reload partitions
  lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' \
    | xargs -r partprobe 2>/dev/null
  udevadm settle --timeout=5

  # check for any partitions
  if lsblk -pn -o NAME,TYPE | grep -q 'part$'; then
    break
  fi

  whiptail --backtitle "$BACKTITLE" --yesno \
    "No partitions detected.\nRetry cfdisk?" 8 60 || exit 1
done

# 6) Function: Prompt user for partition path
input_partition() {
  local title="$1"
  local required=${2:-true}
  local part

  while :; do
    part=$(whiptail --backtitle "$BACKTITLE" --title "$title" \
      --inputbox "Enter device path (e.g. /dev/sda1):" \
      10 60 \
      3>&1 1>&2 2>&3) || exit 1

    # allow empty if not required
    if [[ -z "$part" && "$required" == false ]]; then
      echo ""
      return
    fi

    # validate block device
    if [[ -b "$part" ]]; then
      echo "$part"
      return
    else
      whiptail --backtitle "$BACKTITLE" --msgbox \
        "Invalid device: $part\nTry again." 8 60
    fi
  done
}

# 7) Format & mount partitions

# Root (mandatory)
ROOT=$(input_partition "Root Partition" true)
mkfs.ext4 "$ROOT" &>/dev/null
mount "$ROOT" /mnt

# EFI (optional)
EFI=$(input_partition "EFI Partition (leave empty to skip)" false)
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI" &>/dev/null
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

# Swap (optional)
SWAP=$(input_partition "Swap Partition (leave empty to skip)" false)
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP" &>/dev/null
  swapon "$SWAP"
fi

# 8) Install base system
whiptail --backtitle "$BACKTITLE" --gauge "Installing base system..." 6 60 0
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed &>/dev/null

# 9) Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 10) Chroot & configure system
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap '
  echo >&2 "✖ Chroot error on line $LINENO: ${BASH_COMMAND}"
  whiptail --msgbox "✖ Chroot error\nLine $LINENO:\n${BASH_COMMAND}" 10 70
  exit 1
' ERR

# Locale
LOCALE=$(whiptail --title "Locale" --inputbox \
  "Enter locale (e.g. en_US.UTF-8):" 10 60 en_US.UTF-8 \
  3>&1 1>&2 2>&3)
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen &>/dev/null
echo "LANG=$LOCALE" > /etc/locale.conf

# Time zone
TZ=$(whiptail --title "Time Zone" --inputbox \
  "Enter time zone (e.g. Europe/Minsk):" 10 60 Europe/Minsk \
  3>&1 1>&2 2>&3)
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
hwclock --systohc &>/dev/null

# Hostname
HOSTNAME=$(whiptail --title "Hostname" --inputbox \
  "Enter hostname:" 10 60 archlinux \
  3>&1 1>&2 2>&3)
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Root password
RPW=$(whiptail --passwordbox "Set root password:" 10 60 \
  3>&1 1>&2 2>&3)
echo "root:$RPW" | chpasswd

# Create non-root user
if whiptail --yesno "Create non-root user?" 10 60; then
  U=$(whiptail --inputbox "Username:" 10 60 user \
    3>&1 1>&2 2>&3)
  useradd -m -G wheel,storage,power -s /bin/bash "$U"
  UPW=$(whiptail --passwordbox "Password for $U:" 10 60 \
    3>&1 1>&2 2>&3)
  echo "$U:$UPW" | chpasswd
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

# 11) Finish
whiptail --backtitle "$BACKTITLE" --msgbox \
  "Installation complete! Reboot and remove the installation media." 8 60

exit 0
