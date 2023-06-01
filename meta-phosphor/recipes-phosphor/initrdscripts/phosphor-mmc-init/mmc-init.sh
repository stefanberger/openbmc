#!/bin/sh

kgetopt ()
{
    _cmdline="$(cat /proc/cmdline)"
    _optname="$1"
    _optval="$2"
    for _opt in $_cmdline
    do
        case "$_opt" in
            "${_optname}"=*)
                _optval="${_opt##"${_optname}"=}"
                ;;
            *)
                ;;
        esac
    done
    [ -n "$_optval" ] && echo "$_optval"
}

write_file_signatures() {
  input="$1"
  typ="$2"

  kids=""
  while read -r line; do
    fn=${line%% "${typ}":*}
    sig=${line#* "${typ}":}
    setfattr -n "security.${typ}" -v "$sig" "$fn" &
    kids="$! $kids"
  done < "${input}"

  # shellcheck disable=SC2086
  wait ${kids}
}

# If securityfs is available and 'no-ima' is not found in /proc/cmdline then
# - load IMA and EVM keys
# - activate EVM if an EVM key was loaded
# - load the IMA policy; in case an IMA appraisal policy is loaded apply
#   the file signatures
#
activate_ima_evm() {
    if ! grep -wq securityfs /proc/filesystems ||
         grep -wq no-ima /proc/cmdline
    then
        return
    fi

    # If not running on QEMU: if secure boot is not enabled then also do not
    # enable IMA & EVM
    if test -z "$(dmesg | grep -i qemu)"
    then
        mount /sys/kernel/debug /sys/kernel/debug -t debugfs
        sb=$(grep 1 /sys/kernel/debug/aspeed/sbc/secure_boot)
        umount /sys/kernel/debug
        if test -z "$sb"
        then
            return
        fi
    fi

    mount -t securityfs securityfs /sys/kernel/security

    for kt in ima evm
    do
        if test -r "$rodir/etc/keys/x509_$kt.der"
        then
            keyctl padd asymmetric "" %keyring:.$kt \
                < "$rodir/etc/keys/x509_$kt.der" >/dev/null \
            && echo "Successfully loaded key onto .$kt keyring"
        fi
    done

    # Activate EVM if .evm keyring exists and is not empty
    if test -w /sys/kernel/security/evm && \
        grep -sq " .evm:" /proc/keys && \
        ! grep -sq " .evm: empty" /proc/keys
    then
        # EVM key loaded, activate it
        evm_act=0x80000002
        if echo "$evm_act" > /sys/kernel/security/evm
        then
            printf "Activated EVM: $(cat /sys/kernel/security/evm) [ activated with 0x%x ]\n" $evm_act
        else
            printf "Error: Failed to activate EVM with 0x%x\n" $evm_act
        fi
    fi

    # Load IMA policy
    ima_policy="$rodir/etc/ima/ima-policy"

    if test -w /sys/kernel/security/ima/policy -a -r "$ima_policy"
    then
        load_ima_policy=false

        # If a signed policy is required ...
        if grep -q -E "^appraise func=POLICY_CHECK" "$ima_policy"
        then
            # ... check that .ima exists and is not empty
            if grep -sq " .ima:" /proc/keys && \
               ! grep -sq " .ima: empty" /proc/keys
            then
                load_ima_policy=true
            else
                echo "Error: Not loading IMA appraise policy since there is no key on .ima"
            fi
        else
            # no signed policy: load it in any case
            load_ima_policy=true
        fi

        if $load_ima_policy
        then
            # If an appraise policy is going to be activated then use signed
            # busybox and libraries from $rodir
            if grep -q \
                -E "appraise .*func=(MMAP_CHECK|BPRM_CHECK)" \
                "$ima_policy"
            then
                # A few files need to be signed once appraisal policy is active
                for typ in ima evm; do
	          grep \
	            -E "^(/usr/bin/busybox|/usr/lib/lib|/usr/lib/ld)" \
	              "/${typ}_file_signatures" | \
                    sed "s|^/usr||" > "/run/${typ}_file_signatures"
                  write_file_signatures "/run/${typ}_file_signatures" "${typ}"
                done
                rm -f /run/*_file_signatures
            fi
            if ! echo "$ima_policy" > /sys/kernel/security/ima/policy; then
                echo "Error: Failed to load IMA policy"
            fi
        fi
    fi
}

fslist="proc sys dev run"
rodir=/mnt/rofs
mmcdev="/dev/mmcblk0"
rwfsdev="/dev/disk/by-partlabel/rwfs"

cd /

# We want to make all the directories in $fslist, not one directory named by
# concatonating the names with spaces
#
# shellcheck disable=SC2086
mkdir -p $fslist

mount dev dev -tdevtmpfs
mount sys sys -tsysfs
mount proc proc -tproc
mount tmpfs run -t tmpfs -o mode=755,nodev

# Wait up to 5s for the mmc device to appear. Continue even if the count is
# exceeded. A failure will be caught later like in the mount command.
count=0
while [ $count -lt 5 ]; do
    if [ -e "${mmcdev}" ]; then
        break
    fi
    sleep 1
    count=$((count + 1))
done

# Move the secondary GPT to the end of the device if needed. Look for the GPT
# header signature "EFI PART" located 512 bytes from the end of the device.
if ! tail -c 512 "${mmcdev}" | hexdump -C -n 8 | grep -q "EFI PART"; then
    sgdisk -e "${mmcdev}"
    partprobe
fi

# There eMMC GPT labels for the rootfs are rofs-a and rofs-b, and the label for
# the read-write partition is rwfs. Run udev to make the partition labels show
# up. Mounting by label allows for partition numbers to change if needed.
udevd --daemon
udevadm trigger --type=devices --action=add
udevadm settle --timeout=10
# The real udevd will be started a bit later by systemd-udevd.service
# so kill the one we started above now that we have the needed
# devices loaded
udevadm control --exit

mkdir -p $rodir
if ! mount /dev/disk/by-partlabel/"$(kgetopt root=PARTLABEL)" $rodir -t ext4 -o ro; then
    /bin/sh
fi

# Determine if a factory reset has been requested
mkdir -p /var/lock
resetval=$(fw_printenv -n rwreset 2>/dev/null)
if gpiopresent=$(gpiofind factory-reset-toggle) ; then
    # gpiopresent contains both the gpiochip and line number as
    # separate words, and gpioget needs to see them as such.
    # shellcheck disable=SC2086
    gpioval=$(gpioget $gpiopresent)
else
    gpioval=""
fi
# Prevent unnecessary resets on first boot
if [ -n "$gpioval" ] && [ -z "$resetval" ]; then
    fw_setenv rwreset "$gpioval"
    resetval=$gpioval
fi
if [ "$resetval" = "true" ] || [ -n "$gpioval" ] && [ "$resetval" != "$gpioval" ]; then
    echo "Factory reset requested."
    if ! mkfs.ext4 -F "${rwfsdev}"; then
        echo "Reformat for factory reset failed."
        /bin/sh
    else
        # gpioval will be an empty string if factory-reset-toggle was not found
        fw_setenv rwreset "$gpioval"
        echo "rwfs has been formatted."
    fi
fi

fsck.ext4 -p "${rwfsdev}"
if ! mount "${rwfsdev}" $rodir/var -t ext4 -o rw; then
    /bin/sh
fi

rm -rf $rodir/var/persist/etc-work/
mkdir -p $rodir/var/persist/etc $rodir/var/persist/etc-work $rodir/var/persist/home/root
mount overlay $rodir/etc -t overlay -o lowerdir=$rodir/etc,upperdir=$rodir/var/persist/etc,workdir=$rodir/var/persist/etc-work

init="$(kgetopt init /sbin/init)"

activate_ima_evm

for f in $fslist; do
    mount --move "$f" "$rodir/$f"
done

exec switch_root $rodir "$init"
