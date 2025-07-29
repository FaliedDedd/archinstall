#!/usr/bin/env bash
set -euo pipefail

BACKTITLE="Arch Installer"
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

# 1) Проверка интернета
while ! ping -c1 8.8.8.8 &>/dev/null; do
  whiptail --backtitle "$BACKTITLE" \
    --yesno "Нет соединения с интернетом.\nПовторить?" 8 60 || exit 1
done
whiptail --backtitle "$BACKTITLE" --msgbox "✓ Интернет работает" 8 60

# 2) Установка необходимых инструментов
for t in whiptail pacstrap genfstab arch-chroot lsblk partprobe udevadm; do
  command -v "$t" &>/dev/null || pacman -Sy --noconfirm "$t"
done

# 3) Выбор раскладки клавиатуры
KEYMAP=$(whiptail --backtitle "$BACKTITLE" --title "Клавиатура" \
  --inputbox "Код раскладки (например, us, ru):" 10 50 us \
  3>&1 1>&2 2>&3) || exit 1
KEYMAP=${KEYMAP:-us}
loadkeys "$KEYMAP" &>/dev/null || loadkeys us &>/dev/null

# 4) Настройка сети
if whiptail --backtitle "$BACKTITLE" --title "Сеть" \
     --yesno "Использовать Wi-Fi? Да: Wi-Fi, Нет: Ethernet" 8 60; then
  systemctl start iwd
  WDEV=$(whiptail --inputbox "Wi-Fi интерфейс (например, wlan0):" 10 50 wlan0 3>&1 1>&2 2>&3) || exit 1
  SSID=$(whiptail --inputbox "SSID сети:" 10 50 3>&1 1>&2 2>&3) || exit 1
  PSK=$(whiptail --passwordbox "Пароль от $SSID:" 10 50 3>&1 1>&2 2>&3) || exit 1
  iwctl station "$WDEV" scan
  iwctl station "$WDEV" connect "$SSID" --passphrase "$PSK"
else
  systemctl start dhcpcd
fi

# 5) Разметка диска
while true; do
  whiptail --msgbox "Сейчас запустится cfdisk.\nСоздайте минимум root-раздел." 12 60
  cfdisk
  lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | xargs -r partprobe
  udevadm settle --timeout=5
  lsblk -pn -o NAME,TYPE | grep -q 'part$' && break
  whiptail --yesno "Разделы не обнаружены.\nПовторить cfdisk?" 8 60 || exit 1
done

# 🔧 Функция с фиксом: переключение раскладки для ввода пути
input_partition() {
  local title="$1"
  local required=${2:-true}
  local part

  while :; do
    loadkeys us  # 💡 Переключаем на английскую раскладку

    part=$(whiptail --backtitle "$BACKTITLE" --title "$title" \
      --inputbox "Введите путь (например, /dev/sda1):" \
      10 60 \
      3>&1 1>&2 2>&3) || exit 1

    if [[ -z "$part" && "$required" == false ]]; then
      echo ""
      return
    fi

    [[ -b "$part" ]] && echo "$part" && return
    whiptail --msgbox "Некорректный путь: $part\nПовторите попытку." 8 60
  done
}

# 6) Форматирование и монтирование
ROOT=$(input_partition "Root раздел" true)
mkfs.ext4 "$ROOT"
mount "$ROOT" /mnt

EFI=$(input_partition "EFI раздел (необязательно)" false)
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI"
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

SWAP=$(input_partition "Swap раздел (необязательно)" false)
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP"
  swapon "$SWAP"
fi

# 7) Установка системы
whiptail --gauge "Установка базовой системы..." 6 60 0
pacstrap /mnt base base-devel linux linux-firmware --noconfirm

# 8) fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 9) Настройки в chroot
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap '
  echo >&2 "✖ Ошибка в chroot на строке $LINENO: ${BASH_COMMAND}"
  whiptail --msgbox "✖ Chroot error\nLine $LINENO:\n${BASH_COMMAND}" 10 70
  exit 1
' ERR

LOCALE=$(whiptail --title "Локаль" --inputbox "Введите локаль (например, en_US.UTF-8):" 10 60 en_US.UTF-8 3>&1 1>&2 2>&3)
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

TZ=$(whiptail --inputbox "Часовой пояс (например, Europe/Minsk):" 10 60 Europe/Minsk 3>&1 1>&2 2>&3)
ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime
hwclock --systohc

HOSTNAME=$(whiptail --inputbox "Имя компьютера:" 10 60 archlinux 3>&1 1>&2 2>&3)
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

RPW=$(whiptail --passwordbox "Пароль для root:" 10 60 3>&1 1>&2 2>&3)
echo "root:$RPW" | chpasswd

if whiptail --yesno "Создать обычного пользователя?" 10 60; then
  U=$(whiptail --inputbox "Имя пользователя:" 10 60 user 3>&1 1>&2 2>&3)
  useradd -m -G wheel,storage,power -s /bin/bash "$U"
  UPW=$(whiptail --passwordbox "Пароль для $U:" 10 60 3>&1 1>&2 2>&3)
  echo "$U:$UPW" | chpasswd
  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# 10) Завершение
whiptail --msgbox "
