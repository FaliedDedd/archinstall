#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────┐
# │              FIX EFIBOOTMGR FAILED TO REGISTER                 │
# └─────────────────────────────────────────────────────────────────┘

echo "Fixing efibootmgr failed to register error..."

# Проверяем, смонтирована ли EFI система
if ! mount | grep -q "/boot"; then
    echo "ERROR: /boot is not mounted!"
    echo "Please mount your EFI partition to /boot first."
    echo "Example: mount /dev/sda1 /boot"
    exit 1
fi

# Проверяем, существует ли каталог EFI
if [[ ! -d "/boot/EFI" ]]; then
    echo "Creating EFI directory structure..."
    mkdir -p /boot/EFI/BOOT
fi

# Переустанавливаем efibootmgr для уверенности
echo "Reinstalling efibootmgr..."
pacman -S --noconfirm efibootmgr

# Проверяем доступность EFI переменных
echo "Checking EFI variables..."
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo "ERROR: EFI variables not available!"
    echo "Make sure you're booted in UEFI mode."
    exit 1
fi

# Убедимся, что efivars смонтированы правильно
if ! mount | grep -q efivarfs; then
    echo "Mounting efivarfs..."
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars
fi

# Проверяем права на efivars
echo "Checking efivars permissions..."
if [[ ! -w /sys/firmware/efi/efivars ]]; then
    echo "Setting efivars permissions..."
    chmod -R 755 /sys/firmware/efi/efivars
fi

# Пробуем установить GRUB снова
echo "Reinstalling GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck

# Генерируем конфигурацию GRUB
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

# Проверяем результат
echo "Checking if boot entry was created..."
if efibootmgr | grep -q "GRUB"; then
    echo "SUCCESS: GRUB boot entry created successfully!"
    efibootmgr
else
    echo "WARNING: Could not create boot entry automatically."
    echo "You may need to create boot entry manually in your BIOS/UEFI settings."
fi

echo "Fix completed!"
