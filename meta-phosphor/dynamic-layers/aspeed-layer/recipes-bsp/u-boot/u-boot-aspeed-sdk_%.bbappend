FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

ASPEED_IMAGE_SIZE_KB = "${FLASH_SIZE}"

SRC_URI += 'file://rootfstype-tmpfs.cfg'