#!/bin/sh

# Get the value of the root env variable found in /proc/cmdline
get_root() {
    _cmdline="$(cat /proc/cmdline)"
    root=
    for opt in $_cmdline
    do
        case $opt in
            root=PARTLABEL=*)
                root=${opt##root=PARTLABEL=}
                ;;
            *)
                ;;
        esac
    done
    [ -n "$root" ] && echo "$root"
}

# If securityfs is available then
# - load IMA and EVM keys
# - activate EVM if an EVM key was loaded
# - load the IMA policy; in case an appraise policy is used adjust PATH so that
#   signed executables from $rodir are used rather than the ones from the
#   initrd
#
# This function requires $rodir to be available.
activate_ima_evm() {
	if ! grep -w "securityfs" /proc/filesystems >/dev/null
	then
		return
	fi

	mount -t securityfs securityfs /sys/kernel/security

	for kt in ima evm
	do
		if test -r "$rodir/etc/keys/x509_$kt.der"
		then
			LD_LIBRARY_PATH=$rodir/usr/lib \
			  "$rodir/bin/keyctl" padd asymmetric '' \
			    %keyring:.$kt \
			    < "$rodir/etc/keys/x509_$kt.der" >/dev/null \
			  && echo "Successfully loaded key onto .$kt keyring"
		fi
	done

	# Activate EVM if .evm keyring exists and is not empty
	if test -w /sys/kernel/security/evm -a \
		-n "$(grep ' .evm:' /proc/keys 2>/dev/null)" -a \
		-z "$(grep ' .evm: empty' /proc/keys 2>/dev/null)"
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
			if test \
			   -n "$(grep ' .ima:' /proc/keys 2>/dev/null)" -a \
			   -z "$(grep ' .ima: empty' /proc/keys 2>/dev/null)"
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
			# If an appraise policy is going to be activated
			# then use executables from $rodir
			if grep -q \
				-E "appraise .*func=(MMAP_CHECK|BPRM_CHECK)" \
				"$ima_policy"
			then
				# Use the signed versions of libraries
				export LD_LIBRARY_PATH="/$rodir/lib:/root/$rodir/lib"
				mount --bind "/$rodir/lib/ld-linux-armhf.so.3" \
						/lib/ld-linux-armhf.so.3
				# Use the signed version of busybox
				mount --bind "/$rodir/bin/busybox.nosuid" \
						/bin/busybox.nosuid
				# Use the signed versions of gpiofind, fsck.ext4, etc.
				export PATH="$rodir/usr/bin:$rodir/usr/sbin:$PATH"
			fi
			if ! echo "$ima_policy" > /sys/kernel/security/ima/policy; then
				echo "Error: Failed to load IMA policy"
			fi
		fi
	fi

	umount /sys/kernel/security
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

mkdir -p $rodir
if ! mount /dev/disk/by-partlabel/"$(get_root)" $rodir -t ext4 -o ro; then
    /bin/sh
fi

# Activate IMA and EVM as soon as rodir is mounted
activate_ima_evm

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

for f in $fslist; do
    mount --move "$f" "$rodir/$f"
done

exec switch_root $rodir /sbin/init
