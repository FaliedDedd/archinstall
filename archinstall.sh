#!/usr/bin/env bash
# Полуграфический инсталлятор Arch Linux с Wi-Fi и KDE
set -euo pipefail
set -x

# Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "Скрипт нужно запускать от root."
  exit 1
fi

# Установка необходимых утилит для интерфейса
pacman -Sy dialog whiptail os-prober grub efibootmgr --needed

#
# 1) Клавиатурная раскладка
#
KEYMAP=$(whiptail --title "Клавиатурная раскладка" \
  --inputbox "Введите код раскладки (например, ru, us):" 10 60 ru 3>&1 1>&2 2>&3)

if [[ -z "$KEYMAP" ]]; then
  KEYMAP=us
fi
loadkeys "$KEYMAP"

#
# 2) Язык интерфейса
#
LANG_CHOICE=$(whiptail --title "Язык интерфейса" --menu "Выберите язык:" 12 50 2 \
  ru_RU.UTF-8 "Русский" \
  en_US.UTF-8 "English" \
  3>&1 1>&2 2>&3)

case "$LANG_CHOICE" in
  ru_RU.UTF-8) export LANG=ru_RU.UTF-8 ;;
  *)           export LANG=en_US.UTF-8 ;;
esac

#
# 3) Сеть: выбор Wi-Fi или провод
#
if whiptail --title "Сеть" --yesno "Подключиться по Wi-Fi вместо провода?" 10 60; then
  pacman -Sy wpa_supplicant networkmanager --needed
  systemctl enable NetworkManager

  # Автовыбор беспроводного интерфейса
  mapfile -t IFACES < <(ls /sys/class/net | grep -E '^wl|^wi')
  DEFAULT_IFACE=${IFACES[0]:-wlan0}

  IFACE=$(whiptail --title "Wi-Fi интерфейс" \
    --inputbox "Введите беспроводной интерфейс:" 10 60 "$DEFAULT_IFACE" \
    3>&1 1>&2 2>&3)

  SSID=$(whiptail --title "Wi-Fi SSID" \
    --inputbox "Имя Wi-Fi сети:" 10 60 3>&1 1>&2 2>&3)

  PASS=$(whiptail --title "Wi-Fi пароль" \
    --passwordbox "Пароль от сети $SSID:" 10 60 3>&1 1>&2 2>&3)

  nmcli device wifi connect "$SSID" password "$PASS" ifname "$IFACE"
else
  pacman -Sy networkmanager --needed
  systemctl enable NetworkManager
fi

#
# 4) Выбор диска
#
DISKS=()
while read -r line; do
  DISKS+=("$line")
done < <(lsblk -dpno NAME,SIZE,MODEL | awk '{$1=$1; print}')

DISK=$(whiptail --title "Выбор диска" \
  --menu "Куда устанавливать Arch?" 20 60 10 \
  "${DISKS[@]}" \
  3>&1 1>&2 2>&3)

[ $? -eq 0 ] || { whiptail --msgbox "Установка отменена." 8 40; exit 1; }

#
# 5) Учетная запись
#
USERNAME=$(whiptail --title "Имя пользователя" \
  --inputbox "Введите имя нового пользователя:" 10 60 3>&1 1>&2 2>&3)

PASSWORD=$(whiptail --title "Пароль" \
  --passwordbox "Введите пароль для $USERNAME (он же станет паролем для root и sudo):" 10 60 3>&1 1>&2 2>&3)

PASSWORD2=$(whiptail --title "Подтверждение пароля" \
  --passwordbox "Повторите пароль:" 10 60 3>&1 1>&2 2>&3)

if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
  whiptail --msgbox "Пароли не совпадают. Перезапустите скрипт." 8 40
  exit 1
fi

#
# 6) NVIDIA-драйверы
#
INSTALL_NVIDIA=false
if whiptail --title "NVIDIA" --yesno "Установить драйверы NVIDIA?" 10 60; then
  INSTALL_NVIDIA=true
fi

#
# 7) Подтверждение параметров
#
USE_WIFI=$(nmcli -t -f GENERAL.STATE device status | grep wlan | grep -q connected && echo "да" || echo "нет")
SUMMARY="Язык: $LANG_CHOICE
Клавиатура: $KEYMAP
Диск: $DISK
Пользователь/пароль: $USERNAME
Wi-Fi подключен: $USE_WIFI
NVIDIA-драйверы: $INSTALL_NVIDIA"

whiptail --title "Параметры установки" --msgbox "$SUMMARY" 15 60

#
# 8) Разметка и монтирование
#
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI Boot" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux Root" "$DISK"

BOOT_PART="${DISK}1"
ROOT_PART="${DISK}2"

mkfs.fat -F32 "$BOOT_PART"
mkfs.ext4 "$ROOT_PART"

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

#
# 9) Установка базовой системы и KDE
#
PKGS=(
  base linux linux-firmware sudo
  nano vim git
  plasma sddm kde-applications
  networkmanager os-prober efibootmgr
)

if $INSTALL_NVIDIA; then
  PKGS+=(nvidia nvidia-utils)
fi

pacstrap /mnt "${PKGS[@]}"

genfstab -U /mnt >> /mnt/etc/fstab

#
# 10) Настройка в chroot
#
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail
set -x

ln -sf /usr/share/zoneinfo/Europe/Minsk /etc/localtime
hwclock --systohc

echo "$LANG_CHOICE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LANG_CHOICE" > /etc/locale.conf

echo "archbox" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 archbox.localdomain archbox
HOSTS

# Создание пользователя и установка одинаковых паролей
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD"       | chpasswd

# Настройка sudo (пароль тот же)
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Включаем сервисы
systemctl enable NetworkManager
systemctl enable sddm

# Устанавливаем загрузчик EFI
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# NVIDIA modeset, если нужно
if $INSTALL_NVIDIA; then
  echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
fi

mkinitcpio -P
EOF

#
# 11) Завершение
#
whiptail --title "Готово" --msgbox "Установка завершена! Перезагрузите систему и войдите как $USERNAME." 10 60
