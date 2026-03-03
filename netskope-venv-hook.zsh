# netskope-venv-hook.zsh
# Auto-patch Python virtual environments with Netskope certificates
#
# Installation: Add to ~/.zshrc:
#   source /path/to/netskope-venv-hook.zsh
#
# Repository: https://github.com/schwarztim/netskope-pem-updater
#

NETSKOPE_CERT_PATH="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
NETSKOPE_MARKER="# === Netskope CA Bundle Appended ==="

# Check if Netskope certificate exists
_netskope_cert_exists() {
    [[ -f "$NETSKOPE_CERT_PATH" ]] || \
        security find-certificate -c "Netskope" /Library/Keychains/System.keychain &>/dev/null
}

# Patch a single cacert.pem file
_patch_cacert() {
    local cacert_file="$1"

    [[ ! -f "$cacert_file" ]] && return 1

    # Skip if already patched
    if grep -q "$NETSKOPE_MARKER" "$cacert_file" 2>/dev/null; then
        return 0
    fi

    # Get certificate content
    local cert_content
    if [[ -f "$NETSKOPE_CERT_PATH" ]]; then
        cert_content=$(cat "$NETSKOPE_CERT_PATH")
    else
        cert_content=$(security find-certificate -a -c "Netskope" -p /Library/Keychains/System.keychain 2>/dev/null)
    fi

    [[ -z "$cert_content" ]] && return 1

    # Append Netskope cert
    {
        echo ""
        echo "$NETSKOPE_MARKER"
        echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Script: netskope-pem-updater"
        echo "$NETSKOPE_MARKER"
        echo ""
        echo "$cert_content"
    } >> "$cacert_file" 2>/dev/null && \
        echo "  \033[0;32m✓\033[0m Patched: $cacert_file"
}

# Find and patch all cacert.pem in a venv directory
_patch_venv_certs() {
    local venv_dir="$1"

    [[ ! -d "$venv_dir" ]] && return 1
    _netskope_cert_exists || return 1

    # Find certifi cacert.pem files
    find "$venv_dir" -name "cacert.pem" -path "*site-packages*certifi*" 2>/dev/null | \
        while read -r cacert; do
            _patch_cacert "$cacert"
        done
}

# Wrapper for python -m venv
venv() {
    local venv_dir="${1:-.venv}"

    echo "Creating virtual environment: $venv_dir"
    python3 -m venv "$venv_dir"

    if [[ $? -eq 0 ]]; then
        echo "Activating and installing certifi..."
        source "$venv_dir/bin/activate"
        pip install --quiet --upgrade pip certifi 2>/dev/null

        if _netskope_cert_exists; then
            echo "Patching Netskope certificates..."
            _patch_venv_certs "$venv_dir"
        fi

        echo "\033[0;32m✓\033[0m Virtual environment ready: $venv_dir"
    fi
}

# Wrapper for uv venv
uvenv() {
    local venv_dir="${1:-.venv}"

    echo "Creating virtual environment with uv: $venv_dir"
    uv venv "$venv_dir"

    if [[ $? -eq 0 ]]; then
        source "$venv_dir/bin/activate"
        uv pip install --quiet certifi 2>/dev/null

        if _netskope_cert_exists; then
            echo "Patching Netskope certificates..."
            _patch_venv_certs "$venv_dir"
        fi

        echo "\033[0;32m✓\033[0m Virtual environment ready: $venv_dir"
    fi
}

# Patch existing venv when activating (if not already patched)
_netskope_post_activate() {
    [[ -z "$VIRTUAL_ENV" ]] && return
    _netskope_cert_exists || return

    # Check if any unpatched certifi files exist
    local unpatched
    unpatched=$(find "$VIRTUAL_ENV" -name "cacert.pem" -path "*site-packages*certifi*" 2>/dev/null | \
        xargs -I {} sh -c "grep -L '$NETSKOPE_MARKER' '{}' 2>/dev/null" | head -1)

    if [[ -n "$unpatched" ]]; then
        echo "\033[1;33m⚠\033[0m  Unpatched Netskope certs detected, patching..."
        _patch_venv_certs "$VIRTUAL_ENV"
    fi
}

# Manual patch command
netskope-patch-venv() {
    local target="${1:-$VIRTUAL_ENV}"

    if [[ -z "$target" ]]; then
        echo "Usage: netskope-patch-venv [venv-path]"
        echo "       Or activate a venv first"
        return 1
    fi

    if [[ ! -d "$target" ]]; then
        echo "Error: Directory not found: $target"
        return 1
    fi

    if ! _netskope_cert_exists; then
        echo "Error: Netskope certificate not found"
        return 1
    fi

    echo "Patching certificates in: $target"
    _patch_venv_certs "$target"
    echo "Done!"
}

# Run patch check when sourcing this file in an active venv
[[ -n "$VIRTUAL_ENV" ]] && _netskope_cert_exists && _netskope_post_activate
