# IMA & EVM can be enabled by adding the following line to conf/local.conf
# OPENBMC_ENABLE_IMAEVM="enforce"

DISTRO_FEATURES:append = \
  "${@bb.utils.contains_any('OPENBMC_ENABLE_IMAEVM', 'enforce log', \
                            'integrity ima', '', d)}"

KERNEL_FEATURES:append = \
  "${@bb.utils.contains('OPENBMC_ENABLE_IMAEVM', 'log', \
                        'features/ima/ima-appraise-bootparam.scc', '', d)}"

IMAGE_CLASSES:append = \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' ima-evm-rootfs', '', d)}"
IMA_EVM_POLICY ?= \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', \
                        '${PHOSPHOR_INTEGRITY_DIR}/conf/ima_policy_appraise_all', \
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

# attr provides getfattr/setfattr & tar allows installation of tools with
# signatures
OBMC_IMAGE_EXTRA_INSTALL:append = \
  "${@bb.utils.contains('DISTRO_FEATURES', 'ima', ' attr tar auditd audispd-plugins', '', d)}"
