FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += '${@bb.utils.contains("DISTRO_FEATURES", "ima", \
    " file://ast2600-config-rootfstype-tmpfs.patch", "", d)}'
