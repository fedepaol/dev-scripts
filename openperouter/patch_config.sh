#!/usr/bin/env bash
set -euxo pipefail

# Patch the cluster configuration for OpenPERouter on SNO.
#
# This script wraps three steps that must run after agent/05_agent_configure.sh
# and before agent/06_agent_create_cluster.sh:
#
#   1. change_dns.sh          — Point api/apps DNS to the bridge IP
#   2. patch_agent_config.sh  — Patch agent-config.yaml and install-config.yaml
#                               with the bridge network configuration
#   3. generate_machineconfig.sh — Generate the OpenPERouter MachineConfig
#                                  manifest
#
# Usage:
#   ./openperouter/patch_config.sh [bridge_ip]

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BRIDGE_IP="${1:-192.168.110.2}"

"${SCRIPTDIR}/change_dns.sh" "${BRIDGE_IP}"
"${SCRIPTDIR}/patch_agent_config.sh" "${BRIDGE_IP}"
"${SCRIPTDIR}/generate_machineconfig.sh"
