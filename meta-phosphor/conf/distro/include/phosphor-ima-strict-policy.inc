# Enable stricter enforcement of appraisal via kernel built-in rules

KERNEL_FEATURES:append = \
  "${@bb.utils.contains_any('OPENBMC_ENABLE_IMAEVM', 'enforce log', \
                            ' features/ima/ima-appraise-strict-policy-module.scc', '', d)}"
KERNEL_FEATURES:append = \
  "${@bb.utils.contains_any('OPENBMC_ENABLE_IMAEVM', 'enforce log', \
                            ' features/ima/ima-appraise-strict-policy-firmware.scc', '', d)}"
KERNEL_FEATURES:append = \
  "${@bb.utils.contains_any('OPENBMC_ENABLE_IMAEVM', 'enforce log', \
                            ' features/ima/ima-appraise-strict-policy-kexec.scc', '', d)}"
