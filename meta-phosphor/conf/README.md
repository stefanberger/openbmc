IMA & EVM Signature Enforcement
===============================

OpenBMC supports IMA & EVM signature enforcement on select build targets.
Currently evb-ast2600 and p10bmc are supported. Once signature enforcement
has been enabled only signed executables and libraries can be run on a
system.

Enabling IMA & EVM for a platform
=================================

Since IMA & EVM signature enforcement is an opt-in feature it requires
that the user add the following line to ``conf/local.conf`` before
(re-)building:

    DISTRO_FEATURES:append="integrity ima"

Once added the build process will sign all files. By default the provided
debugging keys from
``meta-security/meta-integrity/data/debug-keys/`` will be used. However, for
production systems users must generate their own keys and make them available
with the following variables in ``conf/local.conf``:

    IMA_EVM_PRIVKEY = "/production/privkey_ima.pem"
    IMA_EVM_X509 = "/production/x509_ima.der"
    IMA_EVM_ROOT_CA = "/production/ima-local-ca.pem"

Instruction for how to generate these keys are provided in the documentation
in ``meta-security/meta-integrity/README.md``.

Verification of IMA & EVM enablement
====================================

When a system with IMA and EVM enabled boots up it will display the
following messages during startup:

    Successfully loaded key onto .ima keyring
    Successfully loaded key onto .evm keyring
    Activated EVM: 2 [ activated with 0x80000002 ]
    [   16.589846] ima: policy update completed

The messages indicate that signature verification keys were loaded onto
kernel keyrings and EVM was activated and the IMA policy was loaded.

On the command prompt the following tests can then be performed.

Display the system's IMA policy:

    root@p10bmc:~# cat /sys/kernel/security/ima/policy
    appraise func=MODULE_CHECK appraise_type=imasig
    appraise func=FIRMWARE_CHECK appraise_type=imasig
    appraise func=KEXEC_KERNEL_CHECK appraise_type=imasig
    appraise func=POLICY_CHECK appraise_type=imasig
    appraise func=MMAP_CHECK mask=MAY_EXEC appraise_type=imasig
    appraise func=BPRM_CHECK appraise_type=imasig

Test run an executable and display its signature (can be different):

    root@p10bmc:~# mount -o remount,rw /
    root@p10bmc:~# xzmore
    Usage: xzmore [OPTION]... [FILE]...
    Like 'more', but operate on the uncompressed contents of xz compressed FILEs.

    Report bugs to <xz@tukaani.org>.

    root@p10bmc:~# getfattr -m ^ -e hex --dump /usr/bin/xzmore
    getfattr: Removing leading '/' from absolute path names
    # file: usr/bin/xzmore
    security.evm=0x0502046730eefd00483046022100a7bf53ae4e3f3482b207fc5b1ef...
    security.ima=0x0302046730eefd0047304502202c9960d7b327ac9c81b2a1ad3e4f6....

Verify that a modified executable (one byte appended) will not run anymore
since its modification invalidated its IMA signature:

    root@p10bmc:~# ls -l /usr/bin/xzmore
    -rwxr-xr-x    1 root     root          2190 Mar  9  2018 /usr/bin/xzmore
    root@p10bmc:~# echo >> /usr/bin/xzmore
    root@p10bmc:~# xzmore
    -sh: /usr/bin/xzmore: /bin/sh: bad interpreter: Permission denied

Restore the file to its original content (remove appended byte) so it has a
valid signature again:

    root@p10bmc:~# truncate -s 2190 /usr/bin/xzmore
    root@p10bmc:~# xzmore
    Usage: xzmore [OPTION]... [FILE]...
    Like 'more', but operate on the uncompressed contents of xz compressed FILEs.

    Report bugs to <xz@tukaani.org>.


Debugging with Audit Log
========================

Failures to execute applications or libraries are audited and the audit log can
be used to determine the reason why applications did not run. The above failure
to run ``xzmore` leaves the following audit log entry:

    root@p10bmc:~# grep type=INTEGRITY /var/log/audit/audit.log
    type=INTEGRITY_DATA msg=audit(1708967244.805:47): pid=1725 uid=0 auid=4294967295
    ses=4294967295 op=appraise_data cause=invalid-signature comm="sh"
    name="/usr/bin/xzmore" dev="mmcblk0p4" ino=1137 res=0 errno=0UID="root"
    AUID="unset"


Disabling IMA & EVM on a system
===============================

There are several ways to turn off IMA & EVM signature enforcement, though
some of them are platform-dependent.

One way to turn it off permanently is to pass ``no-ima`` on the Linux command
line. For this one should inspect the firmware environment variables using the
``fw_printenv`` and find the appropriate variable to change. On a p10bmc this
can then be done with the following command line:

    fw_setenv bootargs 'console=ttyS4,115200n8 no-ima'

On evb-ast2600 the following command line can be used:

    fw_setenv bootargs 'console=ttyS4,115200n8 root=/dev/ram rootfstype=tmpfs rw no-ima'

Once the system is rebooted it will not show the above shown lines during
startup.

To re-enable signature enforcement remove ``no-ima`` from the above command
lines.

On a p10bmc it is also possible to disable the secure boot jumper to turn
off signature enforcement permanently.


Installing additional software
==============================

Any additional software that needs to be installed on a system with IMA & EVM
signatures enabled must be signed. The key used for signing executables and
libraries must have the X509 certificate with the public key installed on the
system and the X509 certificate must be certified by a key that is built
into Linux kernel. Therefore, it will most often be necessary to use the same
key that was used for signing the system to also sign additional software.

If the private key is available on the OpenBMC system then the files can be
signed there directly using ``evmctl``:

    evmctl sign --imasig -a sha256 --portable --m32 \
        --key privkey_ima.pem test.sh

In other case where the signing key is not available on the BMC, software may
need to be install using ``tar``. The following shows an example how this
can be done.

Create a simple test program (as root) on a host where the file signing keys
are available and sign it. The uid, gid, and a file's mode bits must be
final when the file is signed since any later modifications to them, including
after installation on the BMC system itself, will invalidate the EVM signature
and the file will not run.

Note that it is important to add the ``--m32`` to the evmctl commmand line if
the platform where the executable will run is 32bit. For a 64bit platform
this parameter must be removed.

    cat <<EOF > test.sh
    #!/bin/sh
    echo Success!
    EOF

    chmod 755 test.sh
    evmctl sign --imasig -a sha256 --portable --m32 \
        --key ~/openbmc/meta-security/meta-integrity/data/debug-keys/privkey_ima.pem \
        ./test.sh
    tar -c --xattrs-include security.ima --xattrs-include security.evm -f test.sh.tar test.sh

Reboot the BMC with ``no-ima`` on the Linux command line as described above.
Then copy ``test.sh.tar`` to the BMC and untar it:

    tar -xv --xattrs-include security.ima --xattrs-include security.evm -f test.sh.tar

Verify that the signatures have been installed:

    getfattr -m ^ -e hex --dump test.sh

Reboot the BMC with signature enforcement re-enabled by removing ``no-ima``
from the boot command line (described above). Then verify that the file runs:

    ./test.sh
    Success!
