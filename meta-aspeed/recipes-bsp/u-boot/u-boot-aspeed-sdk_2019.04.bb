require u-boot-common-aspeed-sdk_${PV}.inc

UBOOT_MAKE_TARGET ?= "DEVICE_TREE=${UBOOT_DEVICETREE}"

require recipes-bsp/u-boot/u-boot.inc

PROVIDES += "u-boot"
DEPENDS += "bc-native dtc-native"

SRC_URI:append:df-phosphor-mmc = " file://u-boot-env-ast2600.txt"
SRC_URI += " \
            file://rsa_oem_dss_key.pem;sha256sum=64a379979200d39949d3e5b0038e3fdd5548600b2f7077a17e35422336075ad4 \
            file://rsa_pub_oem_dss_key.pem;sha256sum=40132a694a10af2d1b094b1cb5adab4d6b4db2a35e02d848b2b6a85e60738264 \
            file://user/ \
           "

SOCSEC_SIGN_KEY ?= "${WORKDIR}/rsa_oem_dss_key.pem"
SOCSEC_SIGN_ALGO ?= "RSA4096_SHA512"
SOCSEC_SIGN_EXTRA_OPTS ?= "--stack_intersects_verification_region=false --rsa_key_order=big"

OTPTOOL_USER_DIR ?= "${WORKDIR}/user"

inherit socsec-sign
inherit otptool

UBOOT_ENV_SIZE:df-phosphor-mmc = "0x10000"
UBOOT_ENV:df-phosphor-mmc = "u-boot-env"
UBOOT_ENV_SUFFIX:df-phosphor-mmc = "bin"
UBOOT_ENV_TXT:df-phosphor-mmc = "u-boot-env-ast2600.txt"

do_compile:append() {
    if [ -n "${UBOOT_ENV}" ]
    then
        MY_UBOOT_ENV_TXT=${WORKDIR}/${UBOOT_ENV_TXT}.adjusted
        cp ${WORKDIR}/${UBOOT_ENV_TXT} ${MY_UBOOT_ENV_TXT}

        # append ima_appraise=log if OPENBMC_ENABLE_IMAEVM == log
        if [ "${@bb.utils.contains('OPENBMC_ENABLE_IMAEVM', 'log', 'yes', '', d)}" = "yes" ]
        then
            if ! grep -q ima_appraise= ${MY_UBOOT_ENV_TXT}
            then
                sed -i "s|^bootargs=\(.*\)|bootargs=\1 ima_appraise=log|" ${MY_UBOOT_ENV_TXT}
            fi
        fi

        # Generate redundant environment image
        ${B}/tools/mkenvimage -r -s ${UBOOT_ENV_SIZE} -o ${WORKDIR}/${UBOOT_ENV_BINARY} ${MY_UBOOT_ENV_TXT}
    fi
}
