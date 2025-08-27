#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │                 УСТАНОВКА ЗАГРУЗЧИКА GRUB BIOS                 │
# └─────────────────────────────────────────────────────────────────┘

#  Settings ────────────────────────────────────────────────────────
DISK="/dev/sda"
ROOT_PARTITION="/dev/sda1"

#  Pre-flight checks ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Запустите скрипт от root"; exit 1; }

# Проверяем, смонтирована ли система
if ! mount | grep -q "/mnt"; then
    echo "Монтируем корневую файловую систему..."
    mount $ROOT_PARTITION /mnt
fi

# Проверяем, что это BIOS система
if [[ -d /sys/firmware/efi ]]; then
    echo "ERROR: Система использует UEFI, но скрипт для BIOS!"
    exit 1
fi

# Монтируем необходимые системы для chroot
echo "Монтируем системные каталоги..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run

# Устанавливаем загрузчик в chroot
echo "Устанавливаем загрузчик GRUB..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

# Устанавливаем GRUB если не установлен
if ! command -v grub-install &> /dev/null; then
    echo "Устанавливаем GRUB..."
    pacman -Sy --noconfirm grub
fi

# Устанавливаем загрузчик на диск
echo "Устанавливаем GRUB на $DISK..."
grub-install --target=i386-pc --recheck --force $DISK

# Генерируем конфигурацию GRUB
echo "Генерируем конфигурацию GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

# Проверяем установку
echo "Проверяем установку загрузчика..."
if [ -f /boot/grub/i386-pc/core.img ]; then
    echo "✓ GRUB успешно установлен!"
else
    echo "✗ Ошибка установки GRUB!"
    exit 1
fi

EOF

# Размонтируем системы
echo "Размонтируем системные каталоги..."
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys
umount /mnt/run

# Проверяем, нужно ли размонтировать корневую
if mount | grep -q "/mnt "; then
    read -p "Размонтировать корневую файловую систему? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        umount /mnt
        echo "Система размонтирована. Можно перезагружаться."
    else
        echo "Корневая файловая система осталась смонтированной."
    fi
fi

echo -e "\n✅ Загрузчик GRUB успешно установлен!"
echo -e "📀 Перезагрузите систему: reboot"
echo -e "🔧 Убедитесь, что в BIOS установлена загрузка с жесткого диска"
