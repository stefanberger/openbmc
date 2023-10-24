FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
             'file://rootfstype-tmpfs.cfg', '', d)}"
