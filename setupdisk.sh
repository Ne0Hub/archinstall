#!/bin/bash

# from https://raw.githubusercontent.com/kentyl/archinstaller/master/install
# See copyright and license, see the LICENSE file.

# Read the README before running this script!
#
# It will most likely damage your computer rendering it unusable and worthless!

set -e

###
### Configuration
###

INS_BAK_DIR='/installation'
INS_DISK="${INS_DISK:-/dev/sda}"
INS_DOC="$INS_BAK_DIR"/README.md
INS_EFI_SIZE='+550M'
INS_TIME_ZONE="${INS_TIME_ZONE:-Asia/Jakarta}"
INS_SWAP_KEY=/etc/SWAP.key
INS_SWAP_SIZE="$(free -m | awk '/^Mem:/ { printf "+%1.fM", $2+1024 }')"

# You'll get prompted for the password if it's not set.
# It's most secure to use that way or pass it into the script environment.
#INS_PASSWORD="foo"

###
### Function defenitions
###

function stderr {
    echo -ne "$@" 1>&2
}

function error {
    stderr "Error: $@"
    return 1
}

if [[ -z "$INS_PASSWORD" ]]; then
    stderr "Enter disk encryption password:\n"
    read -s ENTER1
    stderr "Enter disk encryption password again:\n"
    read -s ENTER2
    if [[ "$ENTER1" != "$ENTER2" ]]; then
        error 'Passwords do not match'
    fi
    INS_PASSWORD="$ENTER1"
    unset ENTER1 ENTER2
fi

function assert_efi_boot {
    if [ ! -d /sys/firmware/efi/efivars ]; then
        error 'MBR boot not supported'
    fi
}

function assert_valid_disk {
    local DISK="$1"
    local OUTPUT

    if ! OUTPUT="$(sfdisk --list "$DISK" 2>/dev/null)"; then
        error "Disk $DISK missing"
    fi
    if echo "$OUTPUT" | grep Start  1>/dev/null; then
        error "Disk $DISK is not empty (it has a partition table)"
    fi
}

function set_time_through_ntp {
    local TIME_ZONE="$1"

    if ! timedatectl set-timezone "$TIME_ZONE" 2>/dev/null; then
        error "Invalid time zone $TIME_ZONE"
    fi
    stderr "Syncronizing time: "
    timedatectl set-ntp true
    while timedatectl status | grep "synchronized: no" 1>/dev/null; do
        sleep 1
        stderr '.'
    done
    stderr 'DONE!\n'
}

function wipe_disk_with_random_data {
    local DISK="$1"

    cryptsetup open --type plain "$DISK" container --key-file /dev/random
    stderr "Erasing disk $DISK with random data: (fill until no more space left)\n\n"
    # "|| true" as disk will be filled until max and then failure
    dd if=/dev/zero of=/dev/mapper/container bs=2M status=progress || true
    stderr "\n\n"
    cryptsetup close container
}

function create_partitions {
    local DISK="$1"
    local EFI_SIZE="$2"
    local SWAP_SIZE="$3"

    sgdisk \
        --clear \
        --new 1::"$EFI_SIZE" \
            --change-name 1:EFI \
            --typecode 1:ef00 \
        --new 2::"$SWAP_SIZE" \
            --change-name 2:LUKS_SWAP \
            --typecode 2:8300 \
        --new 3:: \
            --change-name 3:LUKS_SLASH \
            --typecode 3:8300 \
        "$DISK" 1>/dev/null
}

function format_fat32 {
    local PARTITION="$1"

    stderr "Formatting $PARTITION with FAT32: "
    mkfs.fat -F32 "$PARTITION" 1>/dev/null
    stderr 'DONE!\n'
}

function cryptsetup_slash {
    local CONTAINER_NAME=SLASH
    local PASSWORD="$1"
    local PARTITION="$2"
    
    # "--key-file -"" is used to take the password
    # from stdin, it won't actually use a file
    stderr "Formatting $PARTITION to hold LUKS container for /: "
    echo "$PASSWORD" | cryptsetup luksFormat "$PARTITION" --key-file -
    stderr 'DONE!\n'
    stderr "Opening LUKS container as $CONTAINER_NAME: "
    echo "$PASSWORD" | cryptsetup open "$PARTITION" "$CONTAINER_NAME" --key-file -
    stderr 'DONE!\n'
    echo "$CONTAINER_NAME"
}

function format_btrfs {
    local PARTITION="$1"

    mkfs.btrfs --label SLASH "$PARTITION" 1>/dev/null
}

function mount_chroot {
    local SLASH_PARTITION="$1"
    local EFI_PARTITION="$2"
    
    stderr "Mounting chroot partitions: "
    mount "$SLASH_PARTITION" /mnt
    mkdir /mnt/boot
    mount "$EFI_PARTITION" /mnt/boot
    stderr 'DONE!\n'
}

function create_key {
    local SWAP_KEY="$1"

    stderr "Creating key file $SWAP_KEY which will be used by swap container: "
    mkdir -p "$(dirname $SWAP_KEY)"
    dd bs=512 count=1 if=/dev/random of="$SWAP_KEY" status=none
    stderr 'DONE!\n'
}

function cryptsetup_swap {
    local CONTAINER_NAME=SWAP
    local PARTITION="$1"
    local SWAP_KEY="$2"

    stderr "Formatting $PARTITION to hold LUKS container for swap: "
    cryptsetup luksFormat --batch-mode "$PARTITION" "$SWAP_KEY"
    stderr 'DONE!\n'
    stderr "Opening LUKS container as $CONTAINER_NAME: "
    cryptsetup open --key-file="$SWAP_KEY" "$PARTITION" "$CONTAINER_NAME"
    stderr 'DONE!\n'
    echo "$CONTAINER_NAME"
}

function set_as_swap {
    local PARTITION="$1"

    stderr "Preparing $PARTITION to be used as swap: "
    mkswap --label SWAP "$PARTITION" 1>/dev/null
    swapon "$PARTITION" 1>/dev/null
    stderr 'DONE!\n'
}

function backup_partition_table {
    local DISK="$1"
    local BAK_DIR="$2"

    local BACKUP_BASENAME="sgdisk-$(basename "$DISK").bin"

    mkdir -p "$BAK_DIR"

    stderr "Backing up partition table: "

    sgdisk -b="$BAK_DIR/$BACKUP_BASENAME" "$DISK" 1>/dev/null

    stderr 'DONE!\n'

    echo "$BACKUP_BASENAME"
}

function backup_luks_header {
    local PARTITION="$1"
    local BAK_DIR="$2"

    local BACKUP_BASENAME="luksHeaderBackup-$(basename "$PARTITION").img"

    mkdir -p "$BAK_DIR"

    stderr "Backing up LUKS header: "

    cryptsetup luksHeaderBackup "$PARTITION" --header-backup-file "$BAK_DIR/$BACKUP_BASENAME"

    stderr 'DONE!\n'

    echo "$BACKUP_BASENAME"
}

function add_documentation {
    local DOC="$1"
    local DISK="$2"
    local SWAP_KEY="$3"
    local BACKUP_PARTITION_TABLE="$4"
    local BACKUP_LUKS_HEADER="$5"

    stderr "Adding documentation: "

    echo -e "# Installation documentation\n" >> "$DOC"

    echo -e "## Before chroot\n" >> "$DOC"

    echo -e "\nInstallation parameters:\n" >> "$DOC"
    
    printf "%-45s | %-35s\n" "Parameter" "Value" >> "$DOC"
    printf "%-45s | %-35s\n" "------" "------" >> "$DOC"
    eval "$(set | grep '^INS_' | grep -v PASSWORD | sed -e 's/INS_//' | sort | sed -r -e 's/([^=]+)=(.*)/printf "%-45s | %-35s\n" \1 \2/')" >> $DOC

    echo -e "\nISO label: \`$(sed -r -e 's/.*archisolabel=([^ ]+).*/\1/' /proc/cmdline)\`" >> "$DOC"

    echo "Installation date: \`$(date --utc)\`" >> "$DOC"

    echo -e "\n### Partitions\n" >> "$DOC"

    echo "Destination disk: \`$DISK\`" >> "$DOC"
    echo "Swap key location: \`$SWAP_KEY\`" >> "$DOC"
    echo "Partition table backup: \`$BACKUP_PARTITION_TABLE\`" >> "$DOC"
    echo "LUKS header backup: \`$BACKUP_LUKS_HEADER\`" >> "$DOC"

    echo -e "\n\`fdisk -l\`:\n" >> "$DOC"
    fdisk -l "$DISK" | sed -e 's/^/    /' >> "$DOC"

    echo -e "\n\`blkid\`:\n" >> "$DOC"
    blkid | egrep "/mapper/|$DISK.:" | sed -e 's/^/    /' >> "$DOC"

    stderr 'DONE!\n'
}


###
### Installation
###

assert_efi_boot

assert_valid_disk "$INS_DISK"

set_time_through_ntp "$INS_TIME_ZONE"

#wipe_disk_with_random_data "$INS_DISK"

create_partitions "$INS_DISK" "$INS_EFI_SIZE" "$INS_SWAP_SIZE"

INS_EFI_PART="${INS_DISK}1"
INS_SWAP_PART="${INS_DISK}2"
INS_SLASH_PART="${INS_DISK}3"

format_fat32 "$INS_EFI_PART"

INS_SLASH_CONTAINER="$(cryptsetup_slash "$INS_PASSWORD" "$INS_SLASH_PART")"

format_btrfs "/dev/mapper/$INS_SLASH_CONTAINER"

mount_chroot "/dev/mapper/$INS_SLASH_CONTAINER" "$INS_EFI_PART"

create_key "/mnt$INS_SWAP_KEY"

INS_SWAP_CONTAINER="$(cryptsetup_swap "$INS_SWAP_PART" "/mnt$INS_SWAP_KEY")"

set_as_swap "/dev/mapper/$INS_SWAP_CONTAINER"

INS_BACKUP_PARTITION_TABLE_BASENAME="$(backup_partition_table "$INS_DISK" "/mnt$INS_BAK_DIR")"

INS_BACKUP_LUKS_HEADER_BASENAME="$(backup_luks_header "$INS_SLASH_PART" "/mnt$INS_BAK_DIR")"

add_documentation "/mnt$INS_DOC" "$INS_DISK" "$INS_SWAP_KEY" "$INS_BAK_DIR/$INS_BACKUP_PARTITION_TABLE_BASENAME" "$INS_BAK_DIR/$INS_BACKUP_LUKS_HEADER_BASENAME"

echo "Success! Follow the Arch Wiki installation instructions from here. It's time to run pacstrap and then go into the arch-chroot.."
