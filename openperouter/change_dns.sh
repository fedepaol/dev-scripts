#!/usr/bin/env bash
set -euxo pipefail

# Point cluster DNS (api + apps wildcard) to the bridge IP.
#
# This script updates two DNS layers:
#   1. Host dnsmasq (NetworkManager) — so oc/curl from the hypervisor resolve
#      api.DOMAIN and *.apps.DOMAIN to the bridge IP.
#   2. Libvirt network DNS — so VMs and get_vips() resolve api.DOMAIN to the
#      bridge IP.
#
# Usage:
#   ./change_dns.sh [bridge_ip]
#
# If bridge_ip is not specified, defaults to 192.168.110.2.
# Expects CLUSTER_NAME and BASE_DOMAIN to be set (or defaults apply).

BRIDGE_IP="${1:-192.168.110.2}"

CLUSTER_NAME="${CLUSTER_NAME:-ostest}"
BASE_DOMAIN="${BASE_DOMAIN:-test.metalkube.org}"
CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
BAREMETAL_NETWORK_NAME="${BAREMETAL_NETWORK_NAME:-${CLUSTER_NAME}bm}"

PATH_CONF_DNSMASQ="/etc/NetworkManager/dnsmasq.d/openshift-${CLUSTER_NAME}.conf"

echo "Updating DNS to point to bridge IP ${BRIDGE_IP}"
echo "  Cluster domain: ${CLUSTER_DOMAIN}"
echo "  Libvirt network: ${BAREMETAL_NETWORK_NAME}"

# ── 1. Host dnsmasq ──────────────────────────────────────────────────────────
# Overwrite the dnsmasq config written by agent/05_agent_configure.sh so that
# api and apps resolve to the bridge IP from the hypervisor.

sudo tee "${PATH_CONF_DNSMASQ}" > /dev/null <<EOF
address=/api.${CLUSTER_DOMAIN}/${BRIDGE_IP}
address=/.apps.${CLUSTER_DOMAIN}/${BRIDGE_IP}
listen-address=::1
cache-size=0
EOF

sudo systemctl reload NetworkManager
echo "Host dnsmasq updated: api + *.apps -> ${BRIDGE_IP}"

# ── 2. Libvirt network DNS ───────────────────────────────────────────────────
# Replace the api host entry in the libvirt network so that VMs (and any
# dig @libvirt-dnsmasq queries) also resolve api.DOMAIN to the bridge IP.

# Find the current api IP so we can delete the old entry first.
OLD_API_IP=$(sudo virsh net-dumpxml "${BAREMETAL_NETWORK_NAME}" \
    | python3 -c "
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin).getroot()
for host in root.findall('.//dns/host'):
    for hn in host.findall('hostname'):
        if hn.text == 'api':
            print(host.get('ip'))
            sys.exit()
" 2>/dev/null || true)

if [ -n "${OLD_API_IP}" ] && [ "${OLD_API_IP}" != "${BRIDGE_IP}" ]; then
    sudo virsh net-update "${BAREMETAL_NETWORK_NAME}" delete dns-host \
        "<host ip='${OLD_API_IP}'><hostname>api</hostname></host>" \
        --live --config
    echo "Removed old api DNS entry (${OLD_API_IP})"
fi

sudo virsh net-update "${BAREMETAL_NETWORK_NAME}" add-last dns-host \
    "<host ip='${BRIDGE_IP}'><hostname>api</hostname></host>" \
    --live --config
echo "Libvirt network updated: api -> ${BRIDGE_IP}"

echo "DNS change complete."
