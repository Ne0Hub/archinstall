ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc --utc
#sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /etc/locale.gen
sed -i '/175/s/^#//g' /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "P4ndArX" > /etc/hostname
echo "127.0.0.1	localhost" > /etc/hosts
echo "::1		localhost" >> /etc/hosts
echo "127.0.1.1	P4ndArX.localdomain	P4ndArX" >> /etc/hosts

passwd
groupadd wm
useradd -m -g wm -G users,wheel,storage,power,network -s /bin/bash -c "William Xhinar" boo
passwd boo

pacman -S vim sudo --noconfirm
#visudo
echo "boo ALL=(ALL) ALL" >> /etc/sudoers

pacman -Syu intel-ucode --noconfirm --force

mkdir -p /run/btrfs-root
vim /etc/mkinitcpio.conf
mkinitcpio -p linux
