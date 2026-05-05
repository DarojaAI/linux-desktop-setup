#!/bin/bash
# Aggregator for all deploy modules (except ai-tools.sh which is optional)
# Sourced by bin/deploy-desktop.sh
# Each module sources lib.sh itself via BASH_SOURCE[0] resolution

set -euo pipefail

# Source all core deploy modules
# Paths are relative to this file's location (scripts/deploy/)
_aggregator_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

source "${_aggregator_dir}/system.sh"
source "${_aggregator_dir}/dev-tools.sh"
source "${_aggregator_dir}/desktop-environment.sh"
source "${_aggregator_dir}/configure.sh"

unset _aggregator_dir
