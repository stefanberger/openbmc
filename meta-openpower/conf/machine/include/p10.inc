include conf/machine/include/ibm-power10-cpu.inc
MACHINE_FEATURES += 'op-fsi'
PREFERRED_PROVIDER_virtual/obmc-host-ctl = "p9-host-start"

IMAGE_CLASSES:append = \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' ima-evm-rootfs', '', d)}"
IMA_EVM_POLICY ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${ASPEED_INTEGRITY_DIR}/conf/ima_policy_appraise_all', \
                        '', d)}"
IMA_EVM_KEY_DIR ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${INTEGRITY_BASE}/data/debug-keys', \
                        '', d)}"
IMA_EVM_PRIVKEY ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${IMA_EVM_KEY_DIR}/privkey_ima.pem', \
                        '', d)}"
IMA_EVM_ROOT_CA ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${IMA_EVM_KEY_DIR}/ima-local-ca.pem', \
                        '', d)}"
IMA_EVM_X509 ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${IMA_EVM_KEY_DIR}/x509_ima.der', \
                        '', d)}"

OBMC_IMAGE_EXTRA_INSTALL:append = \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' attr', '', d)}"
