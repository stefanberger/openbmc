FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

ASPEED_IMAGE_SIZE_KB = "${FLASH_SIZE}"

SRC_URI += '${@bb.utils.contains("DISTRO_FEATURES", "ima", \
    " file://ast2600-config-rootfstype-tmpfs.patch", "", d)}'
