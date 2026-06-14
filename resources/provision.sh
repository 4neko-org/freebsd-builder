#!/bin/sh

# Environment variables:
# OS_VERSION: the version of FreeBSD
# SECONDARY_USER: the username of the secondary user to create
# PKG_SITE_ARCHITECTURE: the name of the architecture used by the pkg site: http://pkg.freebsd.org

set -exu

#ABI_VERSION="$(echo $OS_VERSION | cut -d . -f 1)"
#PACKAGE_SITE="https://pkg.FreeBSD.org/FreeBSD:$ABI_VERSION:$PKG_SITE_ARCHITECTURE/quarterly/Latest"
#IGNORE_OSVERSION=yes
ASSUME_ALWAYS_YES=yes

#export IGNORE_OSVERSION
export ASSUME_ALWAYS_YES

configure_boot_flags() {
  cat <<EOF >> /boot/loader.conf
autoboot_delay="-1"
console="comconsole"
EOF
}

configure_sendmail() {
  sysrc sendmail_enable=NO
  sysrc sendmail_submit_enable=NO
  sysrc sendmail_outbound_enable=NO
  sysrc sendmail_msp_queue_enable=NO
}

install_extra_packages() {
  cat /etc/pkg/FreeBSD.conf

  mv /etc/pkg/FreeBSD.conf /etc/pkg/FreeBSD_temp.conf
  sed '/${ABI}\//s/quarterly/latest/' /etc/pkg/FreeBSD_temp.conf > /etc/pkg/FreeBSD_temp1.conf
  sed '/^FreeBSD-base/,/^}/ s/enabled: no/enabled: yes/' /etc/pkg/FreeBSD_temp1.conf > /etc/pkg/FreeBSD.conf
  echo -n "quarterly -> latest"

  cat /etc/pkg/FreeBSD.conf
  
  pkg bootstrap -y
  
  sleep 1
  
  pkg update -f
  pkg upgrade 

  uname -a
  
  pkg install sudo bash curl rsync openssl git
}

configure_sudo() {
  mkdir -p /usr/local/etc/sudoers.d
  cat <<EOF > "/usr/local/etc/sudoers.d/$SECONDARY_USER"
Defaults:$SECONDARY_USER !requiretty
$SECONDARY_USER ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 440 "/usr/local/etc/sudoers.d/$SECONDARY_USER"
}

setup_secondary_user() {
  pw useradd "$SECONDARY_USER" -m -s "$SHELL" -w none
}

setup_rust_rustup(){
  su $SECONDARY_USER -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" -
  
  su $SECONDARY_USER -c "PATH=\"\$HOME/.cargo/bin:\$PATH\" rustup toolchain install nightly"
  su $SECONDARY_USER -c "PATH=\"\$HOME/.cargo/bin:\$PATH\" rustup toolchain install beta"
}

configure_boot_scripts() {
  cat <<EOF >> /etc/rc.conf
RESOURCES_MOUNT_PATH='/mnt/resources'

mount_resources_disk() {
  # get the last disk
  disk="/dev/\$(sysctl -n kern.disks | grep -o 'vtbd1')"

  if [ -n "\$disk" ]; then
    mkdir -p "\$RESOURCES_MOUNT_PATH"
    mount_msdosfs "\$disk" "\$RESOURCES_MOUNT_PATH"
  fi
}

install_authorized_keys() {
  echo "install_authorized_keys"
  if [ -s "\$RESOURCES_MOUNT_PATH/KEYS" ]; then
    echo "disk exists install_authorized_keys"
    mkdir -p "/home/$SECONDARY_USER/.ssh"
    cp "\$RESOURCES_MOUNT_PATH/KEYS" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chown "$SECONDARY_USER" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chmod 600 "/home/$SECONDARY_USER/.ssh/authorized_keys"
  fi
}

mount_freya_disk() {
  disk="/dev/\$(sysctl -n kern.disks | grep -o 'vtbd2')"

  if [ -n "\$disk" ]; then
    newfs -U -L storage "\${disk}"
    mount "\${disk}a" "/home/$SECONDARY_USER/storage"
    chown "$SECONDARY_USER:$SECONDARY_USER" "/home/$SECONDARY_USER/storage"
  fi
}

mount_resources_disk
install_authorized_keys
mount_freya_disk
EOF
}

setup_freya_home_directory() {
  local work_directory="/home/$SECONDARY_USER"
  local permissions="$SECONDARY_USER:$SECONDARY_USER"

  mkdir "$work_directory/storage"
  chown "$permissions" "$work_directory/storage"

  mkdir "$work_directory/.ssh"
  chown "$permissions" "$work_directory/.ssh"

  cat <<EOF >> $work_directory/env.toml
# if system supports RUSTUP, then a path to the rustup binary dir
# should be set. It uses the same path to access cargo and switch 
# between channels.
[[envs]]
key = "FREYA_RUSTUP_DIR_PATH"
value = "\${HOMEDIR}/.cargo/bin"

[[envs]]
key = "PATH"
value = "\${HOMEDIR}/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# a default toolchain name. A value is a full toolchain name
# channel-arch-hw-os-abi
[[envs]]
key = "FREYA_DEFAULT_TOOLCHAIN"
value = "stable-x86_64-unknown-freebsd"
EOF

  chown "$permissions" "$work_directory/env.toml"
}

setup_freyashell() {
  su $SECONDARY_USER -c "

  PATH=\"\$HOME/.cargo/bin:\$PATH\"
  
  cd /home/$SECONDARY_USER
  git clone --branch v0.1.0 https://codeberg.org/4neko/freyashell.git
  cd ./freyashell
  cargo build --release
  "

  mkdir -p /usr/local/bin
  cp /home/$SECONDARY_USER/freyashell/target/release/freyashell /usr/local/bin/freyashell

  rm -rf /home/$SECONDARY_USER/freyashell

  # set the shell
  echo "/usr/local/bin/freyashell" >> /etc/shells

  # set freya user to work with freyashell
  chsh -s /usr/local/bin/freyashell $SECONDARY_USER
}

configure_tmpfs(){
  echo "varmfs=YES" >> /etc/rc.conf
  echo "varsize=400m" >> /etc/rc.conf
  echo "tmpfs=YES" >> /etc/rc.conf
  echo "tmpsize=256m" >> /etc/rc.conf
}

configure_fstab() {
  cp /etc/fstab /tmp/fstab
  sed '/ufs\t/s/rw/ro/' /tmp/fstab > /etc/fstab
  echo -e "tmpfs\t/home/$SECONDARY_USER/.ssh\ttmpfs\trw,size=200m,mode=1777\t0\t0" >> /etc/fstab

  mkdir -p "/mnt/resources"
}

hardening_sysctl(){
 # if needed
}

configure_boot_flags
configure_sendmail
install_extra_packages
setup_secondary_user
configure_sudo
setup_rust_rustup
configure_boot_scripts
setup_freya_home_directory
setup_freyashell
configure_tmpfs
configure_fstab
hardening_sysctl
