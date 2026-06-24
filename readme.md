# FreeBSD Builder

<img src="https://cdn.4neko.org/freya/vm_freebsd.webp" width="250"/>


This project builds a QEMU VM Image for the [freya](https://codeberg.org/4neko/freya)

This project is based on
[cross-platform-actions/freebsd-builder](https://github.com/cross-platform-actions/freebsd-builder)
GitHub action. The image contains a standard FreeBSD installation without any
X components. It will install the following distribution sets:

* baze.txz
* kernel.txz

In addition to the above file sets, the following packages are installed as well:

* bash
* curl
* pkgin
* rsync
* sudo
* openssl
* git

The follwoing packages are built:
* freyashell

BIOS:
EFI OVMF.fd


Disk layout:
```text
/dev/vtbd0p2 on / (ufs, local, read-only)
devfs on /dev (devfs)
/dev/vtbd1 on /mnt/resources (msdosfs, local)
/dev/vtbd2a on /home/freya/storage (ufs, local, soft-updates)
/dev/vtbd0p1 on /boot/efi (msdosfs, local)
tmpfs on /home/freya/.ssh (tmpfs, local)
tmpfs on /tmp (tmpfs, local)
tmpfs on /var (tmpfs, local)
```

Attached images:
```text
DISK1:
An image of the disk formatted as msdosfs with the following directory layout:

/KEYS - authorized_keys which will be copied to /home/freya/.ssh/


DISK2:
An image of the disk non-formatted, large enough (to fit the code and building) where 
all the files received over freyashell will be installed. The VM will format and mount
the disk manually.

DISK3:
An image of the disk non-formatted, large enough as you expect to have the swap in the system.
Optional. If this disk is not added, the system will operate without swap.
```

!!! Make sure that both disks are attached to VM because each is strictly binded by its order. 
Even if you don't need DISK1 i.e you will use default passwords, attach a dummy disk which is not 
necessary to format.

The `/` is mounted as read-only. The `freya's` homedir is also read-only.

Except for the root user, there's one additional user, `freya`, which is the
user that will be running the [freyashell](https://codeberg.org/4neko/freyashell). 
This user can use `sudo` with a password.

The default password for the `root` is `runner`.


## Architectures and Versions

The following architectures and versions are supported:

| Version | x86-64 | ARM64 |
|---------|--------|-------|
| 15.1    | ✓      | ✓     |
| 15.0    | ✓      | ✓     |
| 14.4    | ✓      | ✓     |

## Building Locally

### Prerequisite

####  [UEFI firmware](https://github.com/tianocore/edk2)

This needs to be located at `resources/ovmf.fd`. Copy the `OVMF.fd` for it's
install location to `resources/ovmf.fd`.

* **Ubuntu** - Install the [`ovmf`](https://packages.ubuntu.com/jammy/ovmf) package.
* **Fedora** - Install the [`edk2-ovmf`](https://fedora.pkgs.org/34/fedora-x86_64/edk2-ovmf-20200801stable-4.fc34.noarch.rpm.html) package.
* **macOS** - Copy the `OVMF.fd` file from a Linux machine

#### Other

* [Packer](https://www.packer.io) 1.7.2 or later
* [QEMU](https://qemu.org)

### Building

1. Clone the repository:
    ```
    git clone https://github.com/4neko-org/freebsd-builder
    cd freebsd-builder
    ```
2. If you running it first time, probably you need to run
    ```
    packer init openbsd.pkr.hcl
    ```

3. Run `build.sh` to build the image:

    ```
    ./build.sh <version> <architecture>
    ```

    Where `<version>` and `<architecture>` are the any of the versions or
    architectures available in the above table.

    ```
    ./build.sh <version> <architecture> -var checksum=<checksum>
    ```

    On non-macOS platforms the `display` variable needs to be overridden by
    specifying `-var display=gtk` or `-var display=sdl` at the end when invoking
    the `build.sh` script:

    ```
    ./build.sh <version> <architecture> -var display=gtk
    ```

    To enable the hardware acceleration during building run

    ```
    ./build.sh <version> <architecture> -var display=gtk -var cpu_type=host
    ```

    Example:

    ```
    ./build.sh 15.0 x86-64 -var display=gtk -var cpu_type=host
    ```

The above command will build the VM image and the resulting disk image will be
at the path: `output/freebsd-15.0-x86-64.qcow2`.


## Additional Information

This VM can be shut down without any gracefull shutdown as the disk is running in 
read-only mode.

At startup, the image will look for a second hard drive (as described above). 
If it presents and it
contains a file named `keys` at the root, it will install this file as the
`authorized_keys` file for the `runner` user. The disk is expected to be
formatted as FAT32. This is used as an alternative to a shared folder between
the host and the guest, since this is not supported by the xhyve hypervisor.
FAT32 is chosen because it's the only filesystem that is supported by both the
host (macOS) and the guest (NetBSD) out of the box.

Also, at startup, the OS will look for the third hard drive (as described above).
If it presents, an OS will `fdisk` the image and invoke `newfs` on the disk
erasing everything which was installed previously. This disk image is a workdisk 
where writing is allowed.


The VM needs to be configured with the `virtio-net` network device. The disk needs to
be configured with the GPT partitioning scheme. And the VM needs to be configured
to use UEFI. All this is required for the VM image to be able to run using the
xhyve hypervisor.

The qcow2 format is chosen because unused space doesn't take up any space on
disk, it's compressible and easily converts the raw format.

## Mounting / altering image without rebuilding

If it is required to alter something in the image (instead of rebuilding it), 
the following should be performed:

1. Log into the VM

2. Run the follwoing

```shell
# mount root as RW
mount -uo rw /

# edit the fstab
vi /etc/fstab

# set the root mount from 'ro' to 'rw' like below
/dev/vtbd0p2	/		ufs	ro	1	1
# to
/dev/vtbd0p2	/		ufs	rw	1	1

# in /etc/rc.conf set mfs to NO
varmfs=NO
varsize=400m
tmpfs=NO
tmpsize=256m

reboot
```

### DO changes

3. After making all necessary changes do the following:

```shell
# in /etc/rc.conf set mfs to NO
varmfs=YES
varsize=400m
tmpfs=YES
tmpsize=256m

# edit the fstab
vi /etc/fstab

# set the root mount from 'ro' to 'rw' like below
/dev/vtbd0p2	/		ufs	rw	1	1
# to
/dev/vtbd0p2	/		ufs	ro	1	1

# reboot machine or shutdown
reboot
```
## Startup example

```
/usr/bin/qemu-system-x86_64 \
    -nodefaults \
    -machine type=q35,accel=hvf:kvm:tcg \
    -cpu host \
    -smp 2 \
    -m 4G \
    -device virtio-net,netdev=user.0,addr=0x03 \
    -netdev user,id=user.0,hostfwd=tcp::65500-:22 \
    -vga std \
    -display sdl \
    -monitor none \
    -serial file:/tmp/NetBSD_10.1_65500.txt \
    -boot strict=off \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -device virtio-blk-pci,drive=drive0,bootindex=0,num-queues=1,write-cache=on \
    -drive if=none,file=/tmp/freebsd-15.0-x86-64.qcow2,id=drive0,cache=unsafe,discard=ignore,format=qcow2
    -device virtio-blk-pci,drive=drive1,bootindex=1 \
    -drive if=none,file=/tmp/test0.qcow2,id=drive1,cache=unsafe,discard=ignore,format=qcow2 \
    -device virtio-blk-pci,drive=drive2,bootindex=2 \
    -drive if=none,file=/tmp/test1.qcow2,id=drive2,cache=unsafe,discard=ignore,format=qcow2
```