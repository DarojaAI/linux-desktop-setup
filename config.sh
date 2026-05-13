#!/bin/bash
# Shared component configuration for deployment and validation
# This file declares all components that deploy-desktop.sh installs
# Both deploy-desktop.sh and tests/validate-install.sh source this file

# Component list format:
#   COMPONENT_NAME: "Display Name"
#   COMPONENT_CHECK: How to verify (command -v, dpkg -l, systemctl, etc.)
#   COMPONENT_REQUIRED: true/false - whether failure should stop deployment

declare -A COMPONENTS

# GNOME Desktop
COMPONENTS[gnome_name]="GNOME Desktop"
COMPONENTS[gnome_check]="dpkg -l gnome-shell 2>/dev/null | grep -q '^ii'"
COMPONENTS[gnome_required]="true"

# xrdp (RDP server)
COMPONENTS[xrdp_name]="xrdp"
COMPONENTS[xrdp_check]="systemctl is-active --quiet xrdp"
COMPONENTS[xrdp_required]="true"

# Visual Studio Code
COMPONENTS[vscode_name]="Visual Studio Code"
COMPONENTS[vscode_check]="command -v code &> /dev/null"
COMPONENTS[vscode_required]="true"

# Claude Code
COMPONENTS[claude_name]="Claude Code"
COMPONENTS[claude_check]="command -v claude &> /dev/null"
COMPONENTS[claude_required]="true"

# OpenRouter CLI
COMPONENTS[openrouter_name]="OpenRouter CLI"
COMPONENTS[openrouter_check]="command -v orc &> /dev/null || command -v openrouter &> /dev/null"
COMPONENTS[openrouter_required]="false"

# Claude Code Router (CCR)
COMPONENTS[ccr_name]="Claude Code Router"
COMPONENTS[ccr_check]="command -v ccr &> /dev/null"
COMPONENTS[ccr_required]="false"

# Chromium Browser
COMPONENTS[chromium_name]="Chromium Browser"
COMPONENTS[chromium_check]="command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null || command -v google-chrome &> /dev/null"
COMPONENTS[chromium_required]="false"

# Node.js (for npm packages)
COMPONENTS[node_name]="Node.js"
COMPONENTS[node_check]="command -v node &> /dev/null"
COMPONENTS[node_required]="false"

# MCP Servers (optional - configured via config file)
COMPONENTS[mcp_name]="MCP Servers"
COMPONENTS[mcp_check]="[[ -f \"\$HOME/.config/desktop-seed/mcp-servers\" ]] && [[ -s \"\$HOME/.config/desktop-seed/mcp-servers\" ]]"
COMPONENTS[mcp_required]="false"

# GitHub CLI
COMPONENTS[ghcli_name]="GitHub CLI"
COMPONENTS[ghcli_check]="command -v gh &> /dev/null"
COMPONENTS[ghcli_required]="false"

# Bun runtime
COMPONENTS[bun_name]="Bun"
COMPONENTS[bun_check]="command -v bun &> /dev/null"
COMPONENTS[bun_required]="false"

# Terraform (IaC tool)
COMPONENTS[terraform_name]="Terraform"
COMPONENTS[terraform_check]="command -v terraform &> /dev/null"
COMPONENTS[terraform_required]="false"

# Terragrunt (Terraform wrapper)
COMPONENTS[terragrunt_name]="Terragrunt"
COMPONENTS[terragrunt_check]="command -v terragrunt &> /dev/null"
COMPONENTS[terragrunt_required]="false"

# OpenCLAW AI client
COMPONENTS[openclaw_name]="OpenCLAW"
COMPONENTS[openclaw_check]="command -v openclaw &> /dev/null"
COMPONENTS[openclaw_required]="false"

# Google Cloud SDK
COMPONENTS[gcloud_name]="Google Cloud SDK"
COMPONENTS[gcloud_check]="command -v gcloud &> /dev/null"
COMPONENTS[gcloud_required]="false"

# Get list of component keys
get_component_keys() {
    local keys=()
    for key in "${!COMPONENTS[@]}"; do
        # Extract component prefix (everything before _name, _check, _required)
        local component="${key%%_*}"
        # Only add if we haven't added this component yet
        if [[ ! " ${keys[*]} " =~ " ${component} " ]]; then
            keys+=("$component")
        fi
    done
    printf '%s\n' "${keys[@]}"
}

# Verify a single component
verify_component() {
    local component="$1"
    local check_var="${component}_check"
    local required_var="${component}_required"
    local name_var="${component}_name"

    local check="${COMPONENTS[$check_var]}"
    local required="${COMPONENTS[$required_var]}"
    local name="${COMPONENTS[$name_var]}"

    if [[ -z "$check" ]]; then
        echo "ERROR: No check defined for $component"
        return 2
    fi

    # Run the check
    if eval "$check" 2>/dev/null; then
        echo "✓ $name installed"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            echo "✗ $name NOT installed (required)"
            return 1
        else
            echo "○ $name NOT installed (optional)"
            return 0
        fi
    fi
}

# Verify all components
verify_all_components() {
    local errors=0
    local components=$(get_component_keys)

    echo "========================================="
    echo "  Validating Components"
    echo "========================================="
    echo ""

    for component in $components; do
        local result
        verify_component "$component"
        result=$?
        if [[ $result -eq 1 ]]; then
            ((errors++))
        elif [[ $result -eq 2 ]]; then
            ((errors++))
        fi
    done

    echo ""
    echo "========================================="
    if [[ $errors -eq 0 ]]; then
        echo "  ✓ All checks passed!"
    else
        echo "  ✗ $errors check(s) failed"
    fi
    echo "========================================="

    return $errors
}
