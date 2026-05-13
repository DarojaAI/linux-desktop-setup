#!/bin/bash
# Post-deployment validation script
# This script automatically validates all components declared in config.sh
# No changes needed when deploy-desktop.sh adds new components

set -euo pipefail

# Get the directory of this script (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the shared component configuration
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Verify all components declared in config.sh
verify_all_components
exit_code=$?

exit $exit_code
