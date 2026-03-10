#!/usr/bin/env bash
set -euxo pipefail

# Inject openperouter quadlets, scripts, and config files into the
# appliance disk image so they are present on the live discovery
# environment.
#
# This must run AFTER "create_appliance" builds appliance.raw and
# BEFORE attach_appliance_diskimage copies it per-node.
#
# Use as POST_APPLIANCE_HOOK.

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ostest}"
OCP_DIR="${OCP_DIR:-ocp/${CLUSTER_NAME}}"

QUADLETS_DIR="${SCRIPTDIR}/quadlets"
CONFIG_DIR="${SCRIPTDIR}/openpeconfig"

APPLIANCE_RAW="${OCP_DIR}/appliance.raw"
if [ ! -f "${APPLIANCE_RAW}" ]; then
  echo "ERROR: ${APPLIANCE_RAW} not found. Run create_appliance first."
  exit 1
fi

# Collect files to inject: source -> dest
# guestfish copy-in copies a local file into the guest at the given directory.
# We build the guestfish commands dynamically.

declare -a GF_CMDS=()

add_file() {
  local src="$1" dest_dir="$2" dest_name="$3" mode="$4"
  if [ ! -f "${src}" ]; then
    echo "ERROR: ${src} not found" >&2
    exit 1
  fi
  GF_CMDS+=("mkdir-p ${dest_dir}")
  GF_CMDS+=("copy-in ${src} ${dest_dir}")
  GF_CMDS+=("chmod ${mode} ${dest_dir}/${dest_name}")
}

# Quadlet files -> /etc/containers/systemd/ (mode 0644)
for f in controllerpod.pod controller.container routerpod.pod frr.container \
         reloader.container frr-sockets.volume openperouter-node-index.service; do
  add_file "${QUADLETS_DIR}/${f}" "/etc/containers/systemd" "${f}" "0644"
done

# Script -> /usr/local/bin/ (mode 0755)
add_file "${QUADLETS_DIR}/openperouter-node-index.sh" "/usr/local/bin" "openperouter-node-index.sh" "0755"

# Config files (mode 0644)
add_file "${CONFIG_DIR}/node-config.yaml" "/var/lib/openperouter" "node-config.yaml" "0644"
add_file "${CONFIG_DIR}/openpe_config.yaml" "/var/lib/openperouter/configs" "openpe_config.yaml" "0644"
add_file "${CONFIG_DIR}/default_bridge" "/etc/ovnk" "default_bridge" "0644"

# Run guestfish to inject all files into the appliance disk image
echo "Injecting openperouter files into ${APPLIANCE_RAW}..."
# Use guestfish -i to auto-inspect and mount the filesystem
GF_SCRIPT=""
for cmd in "${GF_CMDS[@]}"; do
  GF_SCRIPT+="${cmd}"$'\n'
done
echo "${GF_SCRIPT}" | sudo guestfish -a "${APPLIANCE_RAW}" -i

echo "Patched ${APPLIANCE_RAW} with openperouter quadlets and config files"
