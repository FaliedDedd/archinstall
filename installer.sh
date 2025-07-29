#!/usr/bin/env bash
set -euo pipefail

BACKTITLE="Arch Installer"
trap '
  echo >&2 "✖ Error on line $LINENO running: ${BASH_COMMAND}"
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
                (no mirrorlist step)
EOF
tput sgr0
sleep 1

# 1) Internet check
while true; do
  if ping -c1 8.8.8.8 &>/dev/null; then
    whiptail --backtitle "$BACKTITLE" --msgbox "✓ Internet OK" 8 60
    break
  else
    whiptail --backtitle "$BACKTITLE" \
      --yesno "No internet. Retry?" 8 60 || exit 1
  fi
done

# 2) Tools
for t in whiptail pacstrap genfstab arch-chroot lsblk parted udevadm partprobe; do
  command -v "$t" &>/dev/null || pacman -Sy --noconfirm "$t" &>/dev/null
done

# 3) Keymap
KEYMAP=$(whiptail --backtitle "$BACKTITLE" --inputbox \
  "Layout (us, ru, etc):" 10 60 us 3>&1 1>&2 2>&3) || exit 1
KEYMAP=${KEYMAP:-us}
loadkeys "$KEYMAP" &>/dev/null || { loadkeys us; KEYMAP=us; }

# 4) Networking (Wi-Fi or Ethernet)
if whiptail --backtitle "$BACKTITLE" --yesno \
     "Use Wi-Fi? (Yes) or Ethernet? (No)" 8 60; then

  systemctl start iwd
  WDEV=$(whiptail --backtitle "$BACKTITLE" --inputbox \
    "Wi-Fi interface (e.g. wlan0):" 10 60 wlan0 3>&1 1>&2 2>&3) || exit 1
  SSID=$(whiptail --backtitle "$BACKTITLE" --inputbox \
    "SSID:" 10 60 3>&1 1>&2 2>&3) || exit 1
  PSK=$(whiptail --backtitle "$BACKTITLE" --passwordbox \
    "Password for $SSID:" 10 60 3>&1 1>&2 2>&3) || exit 1

  iwctl station "$WDEV" scan &>/dev/null
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK" &>/dev/null
else
  systemctl start dhcpcd
fi

# 5) Partitioning loop
while true; do
  whiptail --backtitle "$BACKTITLE" --msgbox \
    "cfdisk:\n - Create root\n - (opt) EFI\n - (opt) swap\nWrite changes and exit." 12 60
  cfdisk

  for d in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/" $1}'); do
    partprobe "$d" || true
  done
  udevadm settle --timeout=5

  lsblk -pn -o NAME,TYPE | grep -q 'part$' && break
  whiptail --backtitle "$BACKTITLE" --yesno \
    "No partitions found. Re-run cfdisk?" 8 60 || exit 1
done

# Helper to pick partitions
select_partition(){
  local title="$1" opts=() dev type size
  while read -r dev type; do
    [[ "$type"=="part" ]] && size=$(lsblk -n -o SIZE "$dev") \
      && opts+=( "$dev" "$size" )
  done < <(lsblk -pn -o NAME,TYPE)

  [[ ${#opts[@]} -gt 0 ]] || return 1
  whiptail --backtitle "$BACKTITLE" --title "$title" \
    --menu "Select:" 15 60 6 "${opts[@]}" 3>&1 1>&2 2>&3
}

# 6) Format & mount
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

# 7) Base install
whiptail --backtitle "$BACKTITLE" --gauge "pacstrap…" 6 60 0
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed &>/dev/null

# 8) fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 9) chroot for config
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap '
  echo >&2 "✖ Chroot error on line $LINENO: ${BASH_COMMAND}"
  whiptail --msgbox "✖ Chroot error\n$LINENO\n${BASH_COMMAND}" 10 70
  exit 1
' ERR

# Locale
LOCALE=$(whiptail --inputbox "Locale (en_US.UTF-8):" 10 60 en_US.UTF-8 3>&1 1>&2 2>&3)
echo "$LOCALE UTF-8" >> /etc/locale.gen; locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Timezone
TZ=$(whiptail --inputbox "Timezone (Europe/Minsk):" 10 60 Europe/Minsk 3>&1 1>&2 2>&3)
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime; hwclock --systohc

# Hostname
HOSTNAME=$(whiptail --inputbox "Hostname:" 10 60 archlinux 3>&1 1>&2 2>&3)
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root pw
RPW=$(whiptail --passwordbox "Root password:" 10 60 3>&1 1>&2 2>&3)
echo "root:$RPW"|chpasswd

# Create user
if whiptail --yesno "Add a non-root user?" 10 60; then
  U=$(whiptail --inputbox "Username:" 10 60 user 3>&1 1>&2 2>&3)
  useradd -m -G wheel,storage,power -s /bin/bash "$U"
  UPW=$(whiptail --passwordbox "Password for $U:" 10 60 3>&1 1>&2 2>&3)
  echo "$U:$UPW"|chpasswd
  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

# GRUB
if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg

EOF

whiptail --backtitle "$BACKTITLE" --msgbox \
  "All done! Reboot and remove media." 8 60

exit 0
