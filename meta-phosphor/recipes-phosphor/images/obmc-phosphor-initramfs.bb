DESCRIPTION = "Small image capable of booting a device. The kernel includes \
the Minimal RAM-based Initial Root Filesystem (initramfs), which finds the \
first 'init' program more efficiently."
LICENSE = "MIT"
# Needed for the set_user_group functions to succeed
DEPENDS += "shadow-native"

inherit core-image

export IMAGE_BASENAME = "obmc-phosphor-initramfs"

BAD_RECOMMENDATIONS += "busybox-syslog"

PACKAGE_INSTALL = "${VIRTUAL-RUNTIME_base-utils} base-passwd ${ROOTFS_BOOTSTRAP_INSTALL} ${INIT_PACKAGE}"
PACKAGE_INSTALL += "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' keyutils attr', '', d)}"
PACKAGE_INSTALL:remove = "shadow"

# When IMA is enabled sign the files in the initrd and have the signatures
# stored in a file
IMAGE_CLASSES:append = \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' ima-evm-rootfs', '', d)}"

IMA_FILE_SIGNATURES_FILE = "/ima_file_signatures"
EVM_FILE_SIGNATURES_FILE = "/evm_file_signatures"

# Init scripts
INIT_PACKAGE = "obmc-phosphor-initfs"
INIT_PACKAGE:df-phosphor-mmc = "phosphor-mmc-init"
# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = "read-only-rootfs"
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"
IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
PACKAGE_EXCLUDE = "shadow"
