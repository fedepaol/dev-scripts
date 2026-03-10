#!/usr/bin/env bash
set -euxo pipefail

# Patch the config-image ISO to inject ENABLE_VIRTUAL_INTERFACES=true
# into the assisted-service environment.
#
# This must run AFTER "openshift-install agent create config-image".
#
# The config-image ISO contains CONFIG.GZ — a gzipped cpio archive with
# the cluster-specific files. We extract it, modify assisted-service.env,
# and rebuild the ISO.

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ostest}"
OCP_DIR="${OCP_DIR:-ocp/${CLUSTER_NAME}}"
CONFIG_IMAGE_DIR="$(realpath "${OCP_DIR}/configimage")"
CONFIG_IMAGE_ISO="${CONFIG_IMAGE_DIR}/agentconfig.noarch.iso"

if [ ! -f "${CONFIG_IMAGE_ISO}" ]; then
  echo "ERROR: ${CONFIG_IMAGE_ISO} not found. Run 'openshift-install agent create config-image' first."
  exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

# ══════════════════════════════════════════════════════════════════════════════
# Part 1: Patch the config-image ISO (ENABLE_VIRTUAL_INTERFACES)
# ══════════════════════════════════════════════════════════════════════════════

isoinfo -i "${CONFIG_IMAGE_ISO}" -x "/CONFIG.GZ;1" | gunzip > "${TMPDIR}/config.cpio"

mkdir -p "${TMPDIR}/root"
cd "${TMPDIR}/root"
cpio -idm --no-absolute-filenames < "${TMPDIR}/config.cpio"

ENV_FILE="${TMPDIR}/root/usr/local/share/assisted-service/assisted-service.env"
if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: assisted-service.env not found in config-image"
  exit 1
fi

if ! grep -q "^ENABLE_VIRTUAL_INTERFACES=" "${ENV_FILE}"; then
  echo "ENABLE_VIRTUAL_INTERFACES=true" >> "${ENV_FILE}"
  echo "Injected ENABLE_VIRTUAL_INTERFACES=true into assisted-service.env"
else
  echo "ENABLE_VIRTUAL_INTERFACES already set"
fi

# Rebuild cpio archive with absolute paths using chroot so cpio resolves
# absolute filenames correctly.
LDSO=$(readelf -l /usr/bin/cpio 2>/dev/null | grep 'interpreter' | sed 's/.*: \(.*\)]/\1/')
cp /usr/bin/cpio "${TMPDIR}/root/.cpio"
cp "${LDSO}" "${TMPDIR}/root/.ld.so"
mkdir -p "${TMPDIR}/root/.libs"
ldd /usr/bin/cpio | awk '/=>/{print $3}' | while read lib; do
    cp "$lib" "${TMPDIR}/root/.libs/"
done

cd "${TMPDIR}/root"
find . -mindepth 1 -not -name '.cpio' -not -name '.ld.so' -not -path './.libs*' \
    | sed 's|^\./|/|' \
    | sudo chroot "${TMPDIR}/root" /.ld.so --library-path /.libs /.cpio -o -H newc \
    > "${TMPDIR}/config-new.cpio"

rm -f "${TMPDIR}/root/.cpio" "${TMPDIR}/root/.ld.so"
rm -rf "${TMPDIR}/root/.libs"

mkdir -p "${TMPDIR}/iso"
gzip -c "${TMPDIR}/config-new.cpio" > "${TMPDIR}/iso/config.gz"
mkisofs -o "${CONFIG_IMAGE_ISO}" -V "agent_configimage" -r "${TMPDIR}/iso/"
echo "Patched ${CONFIG_IMAGE_ISO} with ENABLE_VIRTUAL_INTERFACES=true"
