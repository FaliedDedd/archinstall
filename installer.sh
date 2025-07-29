#!/usr/bin/env bash
set -euo pipefail

trap 'echo "Ошибка на строке $LINENO"; exit 1' ERR

# Проверка наличия необходимых утилит
for cmd in whiptail reflector pacstrap genfstab arch-chroot; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Требуемая утилита '$cmd' не найдена. Установите её перед запуском."
    exit 1
  fi
done

# 1. Клавиатурная раскладка
KEYMAP=$(whiptail --title "Клавиатурная раскладка" \
  --inputbox "Введите код раскладки (например, ru, us):" 10 60 ru 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then echo "Отменено пользователем."; exit 1; fi
KEYMAP=${KEYMAP:-us}
if ! loadkeys "$KEYMAP"; then
  echo "Невозможно загрузить '$KEYMAP'. Применяем 'us'."
  loadkeys us
  KEYMAP=us
fi
echo "Раскладка: $KEYMAP"

# 2. Зеркала пакетов
COUNTRY=$(whiptail --title "Страна для зеркал" \
  --inputbox "Введите двухбуквенный код страны (например, ru):" 10 60 ru 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then echo "Отменено."; exit 1; fi
COUNTRY=${COUNTRY,,}
echo "RankMirrors: страна = $COUNTRY"
reflector --country "$COUNTRY" --age 12 --protocol https \
  --sort rate --save /etc/pacman.d/mirrorlist

# 3. Настройка сети
if whiptail --title "Тип подключения" --yesno \
   "Вы используете Wi-Fi?\nYes — Wi-Fi, No — Ethernet" 10 60; then
  echo "Запускаем iwd..."
  systemctl start iwd
  iwctl --passphrase "" station device scan
  NETWORK=$(whiptail --title "Точка доступа" \
    --inputbox "Введите SSID и пароль через пробел:" 10 60 3>&1 1>&2 2>&3)
  SSID=${NETWORK%% *}
  PSK=${NETWORK#* }
  iwctl station device connect "$SSID" --passphrase "$PSK"
else
  echo "Ethernet — предполагаем автоконфигурацию DHCP"
  systemctl start dhcpcd
fi

# 4. Разметка диска (ручная)
whiptail --title "Разметка диска" --msgbox \
         "Откроется cfdisk. Пожалуйста, создайте разделы\n- root\n- (опционально) EFI\n- (опционально) swap\nЗатем сохраните и выйдите." 10 60
cfdisk

# 5. Форматирование и монтирование
ROOT=$(whiptail --title "Корневой раздел" \
  --inputbox "Укажите устройство root (например, /dev/sda1):" 10 60 3>&1 1>&2 2>&3)
[[ -n "$ROOT" ]] || { echo "Root не указан."; exit 1; }
mkfs.ext4 "$ROOT"
mount "$ROOT" /mnt

EFI=$(whiptail --title "EFI-раздел" --inputbox \
   "Укажите устройство EFI или оставьте пустым:" 10 60 3>&1 1>&2 2>&3)
if [[ -n "$EFI" ]]; then
  mkfs.fat -F32 "$EFI"
  mkdir -p /mnt/boot
  mount "$EFI" /mnt/boot
fi

SWAP=$(whiptail --title "Swap-раздел" --inputbox \
   "Укажите устройство swap или оставьте пустым:" 10 60 3>&1 1>&2 2>&3)
if [[ -n "$SWAP" ]]; then
  mkswap "$SWAP"
  swapon "$SWAP"
fi

# 6. Установка базовой системы
pacstrap /mnt base base-devel linux linux-firmware --noconfirm --needed

# 7. Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 8. Конфигурация в chroot
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail
trap 'echo "Ошибка во 2-м этапе на строке $LINENO"; exit 1' ERR

# Локализация
LOCALE=$(whiptail --title "Локаль" \
  --inputbox "Введите локаль (пример: en_US.UTF-8 ru_RU.UTF-8):" 10 60 en_US.UTF-8 3>&1 1>&2 2>&3)
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Часовой пояс
TZ=$(whiptail --title "Часовой пояс" \
  --inputbox "Например, Europe/Moscow:" 10 60 Europe/Moscow 3>&1 1>&2 2>&3)
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
hwclock --systohc

# Имя хоста
HOSTNAME=$(whiptail --title "Имя хоста" \
  --inputbox "Введите hostname:" 10 60 archlinux 3>&1 1>&2 2>&3)
echo "$HOSTNAME" > /etc/hostname
{
  echo "127.0.0.1   localhost"
  echo "::1         localhost"
  echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME"
} >> /etc/hosts

# Пароль root
PASS_ROOT=$(whiptail --title "Пароль root" \
  --passwordbox "Установите пароль для root:" 10 60 3>&1 1>&2 2>&3)
echo "root:${PASS_ROOT}" | chpasswd

# Создание пользователя
if whiptail --title "Добавить пользователя" --yesno \
         "Создать нового пользователя?" 10 60; then
  USERNAME=$(whiptail --title "Имя пользователя" \
    --inputbox "Введите имя пользователя:" 10 60 user 3>&1 1>&2 2>&3)
  useradd -m -G wheel,storage,power -s /bin/bash "$USERNAME"
  PASS_USER=$(whiptail --title "Пароль пользователя" \
    --passwordbox "Установите пароль для $USERNAME:" 10 60 3>&1 1>&2 2>&3)
  echo "${USERNAME}:${PASS_USER}" | chpasswd
  sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
fi

# Установка загрузчика
if [[ -d /sys/firmware/efi ]]; then
  pacman -Sy --noconfirm grub efibootmgr
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  pacman -Sy --noconfirm grub
  grub-install --target=i386-pc /dev/sda
fi
grub-mkconfig -o /boot/grub/grub.cfg

EOF

echo "Установка завершена! Перезагрузите систему и удалите установочный носитель."
