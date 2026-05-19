#!/bin/bash
# System baseline hardening for Ubuntu/Debian desktop VMs
# Idempotent: safe to re-run on existing VMs without disruption
# Source this from deploy-desktop.sh or run standalone
#
# SKIPS:
#   SKIP_BASELINE=true        - Skip entire module
#   SKIP_SWAP=true            - Skip swap configuration
#   SKIP_SYSCTL=true          - Skip kernel tuning
#   SKIP_LIMITS=true          - Skip file descriptor limits
#   SKIP_JOURNALD=true        - Skip log size caps
#   SKIP_AUTO_UPDATES=true    - Skip unattended-upgrades
#   SKIP_TIMEZONE=true        - Skip timezone setup
#   SKIP_FSTRIM=true          - Skip SSD TRIM timer
#   SKIP_UNUSED_SERVICES=true - Skip disabling cups/avahi

set -euo pipefail

# Resolve lib.sh from sibling location
_lib_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "${_lib_sh_dir}/lib.sh" ]]; then
	source "${_lib_sh_dir}/lib.sh"
else
	echo "WARNING: lib.sh not found in ${_lib_sh_dir}, using plain echo"
	log_step() { echo "=== $1 ==="; }
	log_info() { echo "  -> $1"; }
	log_warn() { echo "  WARN: $1"; }
	log_error() { echo "  ERROR: $1"; }
fi
unset _lib_sh_dir

# -----------------------------------------------------------------------------
# 1. PERSISTENT SWAP (4GB)
# -----------------------------------------------------------------------------
baseline_swap() {
	[[ "${SKIP_SWAP:-false}" == "true" ]] && return 0
	log_step "Configuring 4GB persistent swap"

	local swapfile="/swapfile"

	# Already active?
	if swapon --show=NAME | grep -q "^${swapfile}$"; then
		log_info "Swap already active at ${swapfile}"
		return 0
	fi

	# Already in fstab but not active? Just activate
	if grep -q "^${swapfile} " /etc/fstab 2>/dev/null; then
		log_info "Swap in fstab but not active; enabling"
		swapon "${swapfile}" 2>/dev/null || {
			log_warn "Existing swapfile may be corrupt; recreating"
			rm -f "${swapfile}"
			_create_swapfile "${swapfile}"
		}
		return 0
	fi

	_create_swapfile "${swapfile}"
}

_create_swapfile() {
	local target="$1"
	log_info "Creating 4GB swap file"

	if ! fallocate -l 4G "${target}" 2>/dev/null; then
		log_warn "fallocate failed, falling back to dd"
		dd if=/dev/zero of="${target}" bs=1M count=4096 status=progress
	fi

	chmod 600 "${target}"
	mkswap "${target}"
	swapon "${target}"

	# Atomic fstab append — idempotent
	if ! grep -qx "${target} none swap sw 0 0" /etc/fstab; then
		echo "${target} none swap sw 0 0" >> /etc/fstab
		log_info "Swap added to /etc/fstab"
	fi

	log_info "Swap active: $(free -h | awk '/^Swap:/ {print $2}') total"
}

# -----------------------------------------------------------------------------
# 2. KERNEL VM TUNING (Bun/Node overcommit, OOM, swappiness)
# -----------------------------------------------------------------------------
baseline_sysctl() {
	[[ "${SKIP_SYSCTL:-false}" == "true" ]] && return 0
	log_step "Tuning kernel virtual memory settings"

	local conf="/etc/sysctl.d/99-openclaw-vm.conf"
	local needs_reload=false

	# Write config if missing or stale
	local desired=$'vm.overcommit_memory = 1\nvm.panic_on_oom = 0\nvm.swappiness = 20'
	if [[ ! -f "${conf}" ]] || [[ "$(cat "${conf}" 2>/dev/null)" != "${desired}" ]]; then
		printf '%s\n' "vm.overcommit_memory = 1" "vm.panic_on_oom = 0" "vm.swappiness = 20" > "${conf}"
		needs_reload=true
		log_info "Wrote ${conf}"
	else
		log_info "${conf} already correct"
	fi

	# Apply only if changed or values differ in runtime
	for key in vm.overcommit_memory vm.panic_on_oom vm.swappiness; do
		local expected="$(echo "${desired}" | grep "^${key}" | cut -d= -f2 | xargs)"
		local current="$(sysctl -n "${key}" 2>/dev/null || echo "unset")"
		if [[ "${current}" != "${expected}" ]]; then
			needs_reload=true
		fi
	done

	if [[ "${needs_reload}" == "true" ]]; then
		sysctl -p "${conf}" >/dev/null
		log_info "Kernel parameters reloaded"
	fi
}

# -----------------------------------------------------------------------------
# 3. FILE DESCRIPTOR & PROCESS LIMITS
# -----------------------------------------------------------------------------
baseline_limits() {
	[[ "${SKIP_LIMITS:-false}" == "true" ]] && return 0
	log_step "Elevating file descriptor and thread limits"

	local conf="/etc/security/limits.d/99-openclaw.conf"

	# Desktop user gets elevated soft limits; hard limit for all
	local desired=$'* soft nofile 65536\n* hard nofile 65536\n* soft nproc 65536\n* hard nproc 65536'

	if [[ ! -f "${conf}" ]] || [[ "$(cat "${conf}" 2>/dev/null)" != "${desired}" ]]; then
		printf '%s\n' "* soft nofile 65536" "* hard nofile 65536" "* soft nproc 65536" "* hard nproc 65536" > "${conf}"
		log_info "Wrote ${conf}"
	else
		log_info "Limits already configured"
	fi

	log_warn "New limits apply to new sessions; current shell unchanged"
}

# -----------------------------------------------------------------------------
# 4. JOURNALD LOG CAP (1GB)
# -----------------------------------------------------------------------------
baseline_journald() {
	[[ "${SKIP_JOURNALD:-false}" == "true" ]] && return 0
	log_step "Capping systemd journal to 1GB"

	local dir="/etc/systemd/journald.conf.d"
	local conf="${dir}/99-max-size.conf"

	mkdir -p "${dir}"

	local desired=$'[Journal]\nSystemMaxUse=1G'
	if [[ ! -f "${conf}" ]] || [[ "$(cat "${conf}" 2>/dev/null)" != "${desired}" ]]; then
		printf '%s\n' "[Journal]" "SystemMaxUse=1G" > "${conf}"
		systemctl restart systemd-journald || log_warn "journald restart failed"
		log_info "Journal capped to 1GB"
	else
		log_info "Journald cap already configured"
	fi
}

# -----------------------------------------------------------------------------
# 5. AUTO SECURITY UPDATES + TIME SYNC
# -----------------------------------------------------------------------------
baseline_auto_updates() {
	[[ "${SKIP_AUTO_UPDATES:-false}" == "true" ]] && return 0
	log_step "Enabling unattended security updates and time sync"

	export DEBIAN_FRONTEND=noninteractive

	# Ensure packages installed
	if ! dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
		apt-get update -y >/dev/null
		apt-get install -y unattended-upgrades systemd-timesyncd >/dev/null
		log_info "Installed unattended-upgrades and timesyncd"
	fi

	# Enable time sync
	if systemctl is-enabled systemd-timesyncd &>/dev/null; then
		log_info "systemd-timesyncd already enabled"
	else
		systemctl enable --now systemd-timesyncd
		log_info "Time sync enabled"
	fi

	# Auto-update config — idempotent
	local apt_conf="/etc/apt/apt.conf.d/20auto-upgrades"
	local desired=$'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";'
	if [[ ! -f "${apt_conf}" ]] || [[ "$(cat "${apt_conf}" 2>/dev/null)" != "${desired}" ]]; then
		printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' > "${apt_conf}"
		log_info "Unattended upgrades configured"
	else
		log_info "Auto-updates already configured"
	fi

	# Enable auto-reboot after kernel updates (security critical)
	local uu_conf="/etc/apt/apt.conf.d/50unattended-upgrades"
	if [[ -f "${uu_conf}" ]]; then
		if ! grep -q 'Unattended-Upgrade::Automatic-Reboot "true"' "${uu_conf}"; then
			sed -i 's|//Unattended-Upgrade::Automatic-Reboot "false"|Unattended-Upgrade::Automatic-Reboot "true"|' "${uu_conf}" || true
			# If uncommented false, change to true
			sed -i 's|Unattended-Upgrade::Automatic-Reboot "false"|Unattended-Upgrade::Automatic-Reboot "true"|' "${uu_conf}" || true
			log_info "Auto-reboot on kernel updates enabled"
		fi
	fi
}

# -----------------------------------------------------------------------------
# 6. TIMEZONE (detect or default to UTC)
# -----------------------------------------------------------------------------
baseline_timezone() {
	[[ "${SKIP_TIMEZONE:-false}" == "true" ]] && return 0
	log_step "Configuring timezone"

	local tz="${VM_TIMEZONE:-UTC}"

	if [[ -f /etc/localtime ]] && [[ "$(readlink -f /etc/localtime)" == "/usr/share/zoneinfo/${tz}" ]]; then
		log_info "Timezone already ${tz}"
		return 0
	fi

	if timedatectl set-timezone "${tz}" 2>/dev/null; then
		log_info "Timezone set to ${tz}"
	else
		log_warn "Failed to set timezone to ${tz}; using system default"
	fi
}

# -----------------------------------------------------------------------------
# 7. SSD TRIM TIMER
# -----------------------------------------------------------------------------
baseline_fstrim() {
	[[ "${SKIP_FSTRIM:-false}" == "true" ]] && return 0
	log_step "Enabling weekly SSD TRIM"

	if systemctl is-enabled fstrim.timer &>/dev/null; then
		log_info "fstrim.timer already enabled"
		return 0
	fi

	if systemctl enable --now fstrim.timer 2>/dev/null; then
		log_info "fstrim.timer enabled (weekly)"
	else
		log_warn "fstrim.timer not available on this system"
	fi
}

# -----------------------------------------------------------------------------
# 8. DISABLE UNUSED DAEMONS (cups, avahi)
# -----------------------------------------------------------------------------
baseline_unused_services() {
	[[ "${SKIP_UNUSED_SERVICES:-false}" == "true" ]] && return 0
	log_step "Disabling unused desktop services"

	local services=("cups" "cups-browsed" "avahi-daemon")
	for svc in "${services[@]}"; do
		if systemctl is-active "${svc}" &>/dev/null || systemctl is-enabled "${svc}" &>/dev/null; then
			systemctl stop "${svc}" 2>/dev/null || true
			systemctl disable "${svc}" 2>/dev/null || true
			log_info "Disabled ${svc}"
		fi
	done
}

# -----------------------------------------------------------------------------
# MAIN ENTRY
# -----------------------------------------------------------------------------
configure_system_baseline() {
	log_info "Starting system baseline configuration (idempotent)"
	baseline_swap
	baseline_sysctl
	baseline_limits
	baseline_journald
	baseline_auto_updates
	baseline_timezone
	baseline_fstrim
	baseline_unused_services
	log_info "System baseline complete"
}

# Standalone execution guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	check_root() {
		if [[ $EUID -ne 0 ]]; then
			echo "ERROR: Must run as root (sudo)" >&2
			exit 1
		fi
	}
	check_root
	configure_system_baseline
fi
