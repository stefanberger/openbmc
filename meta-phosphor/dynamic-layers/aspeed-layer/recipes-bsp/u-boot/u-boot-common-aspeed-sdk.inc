FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
             'file://rootfstype-tmpfs.cfg', '', d)}"

do_configure:append() {
    # Append ima_appraise=log to bootargs if OPENBMC_ENABLE_IMAEVM = "log"
    if [ "${@bb.utils.contains('OPENBMC_ENABLE_IMAEVM', 'log', 'yes', '', d)}" = "yes" ] && [ -f .config ] ; then
        if ! grep -q ima_appraise= .config ; then
            sed -i 's|^CONFIG_BOOTARGS="\(.*\)"\s*|CONFIG_BOOTARGS="\1 ima_appraise=log"|' .config
        fi
    fi
}
