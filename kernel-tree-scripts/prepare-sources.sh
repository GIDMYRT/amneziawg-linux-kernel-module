#!/bin/bash

KERNEL_VERSION=$1

is_modern_kernel() {
  local modern=$(echo $KERNEL_VERSION | awk 'BEGIN{ FS="."};
      { if ($1 < 5) { print "N"; }
        else if ($1 == 5) {
            if ($2 <= 5) { print "N"; }
            else { print "Y"; }
        }
        else { print "Y"; }
      }')

  if [ "$modern" = "N" ]; then
    return 1
  fi
}

cd_first () {
  local prefix=$1
  local first=$(find ./${prefix}* -maxdepth 0 -type d 2>/dev/null | sort | head -n 1)
  [ "${first}" != "" ] && cd "${first}" || exit 255
}

if ! is_modern_kernel; then
  echo "Legacy kernel - using the compat sources"
  exit 0
fi

if [ -e kernel/drivers/net/wireguard/main.c ] && [ -e kernel/include/uapi/linux/wireguard.h ]; then
  echo "Kernel sources are already prepared, skipping"
  exit 0
fi

if ! which apt-get > /dev/null 2>&1 && \
   ! which dnf > /dev/null 2>&1 && \
   ! which yum > /dev/null 2>&1; then
  echo "You need to download sources on your own and make a symbolic link to /usr/src/amneziawg-1.0.0/kernel:"
  echo ""
  echo "  ln -s /path/to/kernel/source /usr/src/amneziawg-1.0.0/kernel"
  echo ""
  echo "Otherwise it is not possible to obtain kernel sources on your system automatically"
  exit 1
fi

DISTRO_FLAVOR=$(cat /etc/*-release 2>/dev/null | grep -E ^ID_LIKE=  | sed 's/ID_LIKE=//' | sed 's/"//g')
DISTRO_FLAVOR=${DISTRO_FLAVOR:-$(cat /etc/*-release 2>/dev/null | grep -E ^ID=  | sed 's/ID=//' | sed 's/"//g')}

if [ "${AWG_TEMP_DIR}" != "" ]; then
  mkdir -p /var/lib/amnezia/amneziawg
  echo "${AWG_TEMP_DIR}" > /var/lib/amnezia/amneziawg/.tempdir
elif [ -f /var/lib/amnezia/amneziawg/.tempdir ]; then
  AWG_TEMP_DIR="$(cat /var/lib/amnezia/amneziawg/.tempdir)"
fi

PREFIX=${AWG_TEMP_DIR:-/tmp}
WORKDIR="${PREFIX}/amneziawg"

[ -d "${WORKDIR}" ] && rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
pushd "${WORKDIR}" > /dev/null 2>&1 || exit 1

echo "Downloading source for Linux kernel version ${KERNEL_VERSION}"

if [[ "${DISTRO_FLAVOR}" =~ debian ]]; then
  export DEBIAN_FRONTEND=noninteractive
  VERSION_MAIN="${KERNEL_VERSION%+*}"
  VERSION_SUFFIX="${KERNEL_VERSION#*+}"
  ac=$(apt-cache search --names-only linux-image "${VERSION_MAIN}" "${VERSION_SUFFIX}" unsigned 2>/dev/null|head -n 1)
  [ "${ac}" == "" ] && ac=$(apt-cache search --names-only linux-image "${VERSION_MAIN}" "${VERSION_SUFFIX}" 2>/dev/null|head -n 1)
  if [ "${ac}" == "" ]; then
    echo "Could not find suitable image for your Linux distribution!"
    exit 255
  fi

  PACKAGE_NAME="${ac% - *}"
  PACKAGE_VERSION=$(apt-cache madison "${PACKAGE_NAME}"|grep Sources|head -n 1|awk '{ print $3; }')
  echo "Downloading as $(whoami)"
  apt-get -yq -o APT::Sandbox::User="$(whoami)" source "${PACKAGE_NAME}=${PACKAGE_VERSION}"
  cd_first
else
  TEMP_DIR=$(mktemp -d -p "${WORKDIR}")
  yumdownloader --source kernel --downloaddir "${TEMP_DIR}"
  rpm -ihv --nodb --nodeps -D "_sourcedir %nil" -D "_specdir %nil" --root "${TEMP_DIR}" "${TEMP_DIR}/*.src.rpm"
  SRC_TAR=$(rpmspec --srpm -q --qf "[%{SOURCE}\n]" "${TEMP_DIR}/kernel.spec" | tail -1)
  SRC_DIR="${TEMP_DIR}/linux_sources"
  mkdir -p "${SRC_DIR}"
  tar -xvf "${TEMP_DIR}/${SRC_TAR}" -C "${SRC_DIR}" --strip-components=1
  cd "${SRC_DIR}"
fi

KERNEL_PATH="$(pwd)"
popd > /dev/null 2>&1 || exit 1
[ -e kernel ] && rm -f kernel
ln -s "${KERNEL_PATH}" kernel
