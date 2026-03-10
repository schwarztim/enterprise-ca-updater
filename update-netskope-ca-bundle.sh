#!/bin/bash
#
# update-netskope-ca-bundle.sh - Enterprise Certificate Store Updater
#
# Updates certificate stores across multiple tools and platforms with
# enterprise SSL inspection certificates (Netskope, Zscaler, etc.).
#
# Author: Tim Schwarz
# Version: 2.0.0
# Repository: https://github.com/schwarztim/enterprise-ca-updater
#

set -euo pipefail

# Configuration
NETSKOPE_DATA_PATH="/Library/Application Support/Netskope/STAgent/data"
NETSKOPE_CERT_FILE="nscacert.pem"
MARKER="# === Netskope CA Bundle Appended ==="
JAVA_KEYSTORE_PASSWORD="changeit"
NETSKOPE_ALIAS="netskope-ca"
SCRIPT_VERSION="2.0.0"

# Default search paths
SEARCH_PATHS=(
    "$HOME"
    "/Library/Frameworks/Python.framework"
    "/usr/local/lib/python*"
    "/opt/homebrew/lib/python*"
)

# Add extra paths from environment
if [[ -n "${NETSKOPE_EXTRA_PATHS:-}" ]]; then
    IFS=':' read -ra EXTRA_PATHS <<< "$NETSKOPE_EXTRA_PATHS"
    SEARCH_PATHS+=("${EXTRA_PATHS[@]}")
fi

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# Stats
UPDATED=0
SKIPPED=0
FAILED=0
JAVA_UPDATED=0
JAVA_SKIPPED=0
JAVA_FAILED=0
GIT_UPDATED=0
NPM_UPDATED=0
PIP_UPDATED=0
SYSTEM_UPDATED=0

# JSON output mode
JSON_OUTPUT=false
JSON_ENTRIES=()

# Logging
log_info()    { [[ "$JSON_OUTPUT" == "true" ]] && return; echo -e "${NC}[INFO] $1${NC}"; }
log_success() { [[ "$JSON_OUTPUT" == "true" ]] && return; echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { [[ "$JSON_OUTPUT" == "true" ]] && return; echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error()   { [[ "$JSON_OUTPUT" == "true" ]] && return; echo -e "${RED}[ERROR] $1${NC}"; }

json_add() {
    local key="$1" value="$2"
    JSON_ENTRIES+=("\"$key\": \"$value\"")
}

# Run external command, suppress stdout in JSON mode
run_quiet() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        "$@" &>/dev/null
    else
        "$@"
    fi
}

print_banner() {
    [[ "$JSON_OUTPUT" == "true" ]] && return
    echo -e "${CYAN}"
    echo "================================================================================"
    echo "                   Enterprise Certificate Store Updater"
    echo "                          macOS/Linux Edition v${SCRIPT_VERSION}"
    echo "================================================================================"
    echo -e "${NC}"
}

print_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat <<JSONEOF
{
  "version": "$SCRIPT_VERSION",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stats": {
    "python": { "updated": $UPDATED, "skipped": $SKIPPED, "failed": $FAILED },
    "java": { "updated": $JAVA_UPDATED, "skipped": $JAVA_SKIPPED, "failed": $JAVA_FAILED },
    "git": { "updated": $GIT_UPDATED },
    "npm": { "updated": $NPM_UPDATED },
    "pip": { "updated": $PIP_UPDATED },
    "system": { "updated": $SYSTEM_UPDATED }
  }
}
JSONEOF
        return
    fi

    echo -e "${CYAN}"
    echo "================================================================================"
    echo "                                  Summary"
    echo "================================================================================"
    echo "    Python Bundles Updated:  $UPDATED"
    echo "    Python Bundles Skipped:  $SKIPPED"
    echo "    Python Bundles Failed:   $FAILED"
    echo "    Java Keystores Updated:  $JAVA_UPDATED"
    echo "    Java Keystores Skipped:  $JAVA_SKIPPED"
    echo "    Java Keystores Failed:   $JAVA_FAILED"
    echo "    Git Configs Updated:     $GIT_UPDATED"
    echo "    npm/yarn/pnpm Updated:   $NPM_UPDATED"
    echo "    pip/conda Updated:       $PIP_UPDATED"
    echo "    System CA Updated:       $SYSTEM_UPDATED"
    echo "================================================================================"
    echo -e "${NC}"
}

# ─── Certificate Loading ────────────────────────────────────────────────────

get_netskope_cert() {
    local cert_path="$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE"

    if [[ -f "$cert_path" ]]; then
        cat "$cert_path"
        return 0
    fi

    # macOS fallback: export from Keychain
    if [[ "$(uname)" == "Darwin" ]]; then
        log_info "Certificate file not found, trying Keychain..."
        local keychain_cert
        keychain_cert=$(security find-certificate -a -c "Netskope" -p /Library/Keychains/System.keychain 2>/dev/null || true)
        if [[ -n "$keychain_cert" ]]; then
            echo "$keychain_cert"
            return 0
        fi
    fi

    # Linux: check common enterprise cert locations
    local linux_paths=(
        "/opt/netskope/data/nscacert.pem"
        "/etc/netskope/nscacert.pem"
        "/opt/zscaler/data/zscaler_root_ca.pem"
        "/usr/local/share/ca-certificates/enterprise-ca.crt"
    )
    for p in "${linux_paths[@]}"; do
        if [[ -f "$p" ]]; then
            log_info "Found enterprise certificate at: $p"
            cat "$p"
            return 0
        fi
    done

    log_error "Could not find enterprise CA certificate"
    log_error "Expected location: $cert_path"
    log_error "Ensure your enterprise SSL client is installed and running"
    return 1
}

# ─── Python Certificate Updates ─────────────────────────────────────────────

has_netskope_cert() {
    local file="$1"
    grep -q "$MARKER" "$file" 2>/dev/null
}

find_cacert_files() {
    local files=()

    for search_path in "${SEARCH_PATHS[@]}"; do
        for expanded_path in $search_path; do
            if [[ -d "$expanded_path" ]]; then
                while IFS= read -r -d '' file; do
                    files+=("$file")
                done < <(find "$expanded_path" -name "cacert.pem" -path "*site-packages*certifi*" -print0 2>/dev/null)
            fi
        done
    done

    printf '%s\n' "${files[@]}" | sort -u
}

update_cert_file() {
    local file="$1"
    local netskope_cert="$2"
    local dry_run="${3:-false}"

    if has_netskope_cert "$file"; then
        log_warning "Skipping (already patched): $file"
        ((SKIPPED++)) || true
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would update: $file"
        return 0
    fi

    local backup_file="${file}.backup_$(date +%Y%m%d_%H%M%S)"
    if ! cp "$file" "$backup_file" 2>/dev/null; then
        log_error "Failed to backup: $file (permission denied?)"
        ((FAILED++)) || true
        return 1
    fi

    {
        echo ""
        echo "$MARKER"
        echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Script: enterprise-ca-updater"
        echo "$MARKER"
        echo ""
        echo "$netskope_cert"
    } >> "$file"

    if [[ $? -eq 0 ]]; then
        log_success "Updated: $file"
        ((UPDATED++)) || true
    else
        log_error "Failed to update: $file"
        mv "$backup_file" "$file" 2>/dev/null
        ((FAILED++)) || true
    fi
}

# ─── Java Keystore Updates ──────────────────────────────────────────────────

find_java_installations() {
    local java_homes=()

    if [[ -n "${JAVA_HOME:-}" ]] && [[ -d "$JAVA_HOME" ]]; then
        java_homes+=("$JAVA_HOME")
    fi

    local search_paths=(
        "/Library/Java/JavaVirtualMachines/*/Contents/Home"
        "/usr/lib/jvm/*"
        "/usr/java/*"
        "/opt/java/*"
        "/opt/jdk/*"
        "$HOME/.sdkman/candidates/java/*"
        "/System/Library/Java/JavaVirtualMachines/*/Contents/Home"
    )

    for pattern in "${search_paths[@]}"; do
        for path in $pattern; do
            if [[ -d "$path" ]] && [[ -f "$path/bin/keytool" ]]; then
                java_homes+=("$path")
            fi
        done
    done

    printf '%s\n' "${java_homes[@]}" | sort -u
}

find_cacerts_files() {
    local cacerts_files=()
    local java_homes
    java_homes=$(find_java_installations)

    while IFS= read -r java_home; do
        [[ -z "$java_home" ]] && continue
        local possible_locations=(
            "$java_home/lib/security/cacerts"
            "$java_home/jre/lib/security/cacerts"
        )
        for cacerts_path in "${possible_locations[@]}"; do
            if [[ -f "$cacerts_path" ]]; then
                cacerts_files+=("$cacerts_path")
            fi
        done
    done <<< "$java_homes"

    local system_locations=(
        "/etc/ssl/certs/java/cacerts"
        "/etc/pki/java/cacerts"
    )
    for cacerts_path in "${system_locations[@]}"; do
        if [[ -f "$cacerts_path" ]]; then
            cacerts_files+=("$cacerts_path")
        fi
    done

    printf '%s\n' "${cacerts_files[@]}" | sort -u
}

has_netskope_in_keystore() {
    local keystore="$1"
    local keytool_cmd

    if command -v keytool &> /dev/null; then
        keytool_cmd="keytool"
    else
        local java_home
        java_home=$(dirname "$(dirname "$(dirname "$keystore")")")
        if [[ -f "$java_home/bin/keytool" ]]; then
            keytool_cmd="$java_home/bin/keytool"
        else
            return 1
        fi
    fi

    "$keytool_cmd" -list -keystore "$keystore" -storepass "$JAVA_KEYSTORE_PASSWORD" -alias "$NETSKOPE_ALIAS" &>/dev/null
}

update_java_keystore() {
    local keystore="$1"
    local cert_file="$2"
    local dry_run="${3:-false}"
    local keytool_cmd

    if command -v keytool &> /dev/null; then
        keytool_cmd="keytool"
    else
        local java_home
        java_home=$(dirname "$(dirname "$(dirname "$keystore")")")
        if [[ -f "$java_home/bin/keytool" ]]; then
            keytool_cmd="$java_home/bin/keytool"
        else
            log_error "keytool command not found for $keystore"
            ((JAVA_FAILED++)) || true
            return 1
        fi
    fi

    if has_netskope_in_keystore "$keystore"; then
        log_warning "Skipping (already present): $keystore"
        ((JAVA_SKIPPED++)) || true
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would update keystore: $keystore"
        return 0
    fi

    local backup_file="${keystore}.backup_$(date +%Y%m%d_%H%M%S)"
    if ! cp "$keystore" "$backup_file" 2>/dev/null; then
        log_error "Failed to backup: $keystore (permission denied?)"
        ((JAVA_FAILED++)) || true
        return 1
    fi

    if "$keytool_cmd" -import -noprompt -trustcacerts \
        -alias "$NETSKOPE_ALIAS" \
        -file "$cert_file" \
        -keystore "$keystore" \
        -storepass "$JAVA_KEYSTORE_PASSWORD" &>/dev/null; then
        log_success "Updated Java keystore: $keystore"
        ((JAVA_UPDATED++)) || true
    else
        log_error "Failed to update keystore: $keystore"
        mv "$backup_file" "$keystore" 2>/dev/null
        ((JAVA_FAILED++)) || true
    fi
}

# ─── Linux System CA Store ──────────────────────────────────────────────────

update_system_ca_store() {
    local cert_file="$1"
    local dry_run="${2:-false}"

    if [[ "$(uname)" == "Darwin" ]]; then
        log_info "macOS detected — system CA managed by Keychain, skipping system store"
        return 0
    fi

    log_info "Detecting Linux distribution CA update method..."

    if command -v update-ca-certificates &>/dev/null; then
        # Debian/Ubuntu
        local dest="/usr/local/share/ca-certificates/enterprise-ca.crt"
        if [[ -f "$dest" ]] && cmp -s "$cert_file" "$dest" 2>/dev/null; then
            log_warning "System CA already installed: $dest"
            return 0
        fi
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would copy to $dest and run update-ca-certificates"
            return 0
        fi
        cp "$cert_file" "$dest" && update-ca-certificates 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Updated Debian/Ubuntu system CA store"
            ((SYSTEM_UPDATED++)) || true
        else
            log_error "Failed to update system CA store"
        fi
    elif command -v update-ca-trust &>/dev/null; then
        # RHEL/Fedora/CentOS
        local dest="/etc/pki/ca-trust/source/anchors/enterprise-ca.pem"
        if [[ -f "$dest" ]] && cmp -s "$cert_file" "$dest" 2>/dev/null; then
            log_warning "System CA already installed: $dest"
            return 0
        fi
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would copy to $dest and run update-ca-trust"
            return 0
        fi
        cp "$cert_file" "$dest" && update-ca-trust extract 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Updated RHEL/Fedora system CA store"
            ((SYSTEM_UPDATED++)) || true
        else
            log_error "Failed to update system CA store"
        fi
    elif command -v trust &>/dev/null; then
        # Arch Linux
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would run trust anchor $cert_file"
            return 0
        fi
        trust anchor "$cert_file" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_success "Updated Arch Linux system CA store"
            ((SYSTEM_UPDATED++)) || true
        else
            log_error "Failed to update system CA store"
        fi
    else
        log_warning "Could not detect system CA update method — skipping"
    fi
}

# ─── Git HTTPS Configuration ────────────────────────────────────────────────

update_git_config() {
    local cert_path="$1"
    local dry_run="${2:-false}"

    if ! command -v git &>/dev/null; then
        log_warning "git not found — skipping git configuration"
        return 0
    fi

    local current
    current=$(git config --global http.sslCAInfo 2>/dev/null || true)
    if [[ "$current" == "$cert_path" ]]; then
        log_warning "git http.sslCAInfo already configured"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would set git config --global http.sslCAInfo $cert_path"
        return 0
    fi

    git config --global http.sslCAInfo "$cert_path"
    log_success "Configured git http.sslCAInfo = $cert_path"
    ((GIT_UPDATED++)) || true
}

# ─── npm/yarn/pnpm Configuration ────────────────────────────────────────────

update_npm_config() {
    local cert_path="$1"
    local dry_run="${2:-false}"

    if command -v npm &>/dev/null; then
        local current
        current=$(npm config get cafile 2>/dev/null || true)
        if [[ "$current" == "$cert_path" ]]; then
            log_warning "npm cafile already configured"
        elif [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would set npm config cafile=$cert_path"
        else
            run_quiet npm config set cafile "$cert_path" 2>/dev/null
            log_success "Configured npm cafile = $cert_path"
            ((NPM_UPDATED++)) || true
        fi
    fi

    if command -v yarn &>/dev/null; then
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would set yarn cafile"
        else
            # yarn v1 vs v2+ have different config commands
            if yarn --version 2>/dev/null | grep -q "^1\."; then
                run_quiet yarn config set cafile "$cert_path" 2>/dev/null && \
                    log_success "Configured yarn v1 cafile = $cert_path"
            else
                log_info "yarn v2+ uses .npmrc — already covered by npm config"
            fi
        fi
    fi

    if command -v pnpm &>/dev/null; then
        log_info "pnpm uses .npmrc — covered by npm cafile configuration"
    fi
}

# ─── pip/conda Configuration ────────────────────────────────────────────────

update_pip_conda_config() {
    local cert_path="$1"
    local dry_run="${2:-false}"

    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        local pip_cmd
        pip_cmd=$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null)
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would set pip config global.cert=$cert_path"
        else
            run_quiet "$pip_cmd" config set global.cert "$cert_path" 2>/dev/null
            log_success "Configured pip global.cert = $cert_path"
            ((PIP_UPDATED++)) || true
        fi
    fi

    if command -v conda &>/dev/null; then
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would set conda ssl_verify=$cert_path"
        else
            run_quiet conda config --set ssl_verify "$cert_path" 2>/dev/null
            log_success "Configured conda ssl_verify = $cert_path"
        fi
    fi
}

# ─── Docker Certificate Configuration ───────────────────────────────────────

update_docker_certs() {
    local cert_file="$1"
    local dry_run="${2:-false}"

    if ! command -v docker &>/dev/null; then
        log_warning "Docker not found — skipping Docker certificate configuration"
        return 0
    fi

    local docker_cert_dir="/etc/docker/certs.d"
    if [[ ! -d "$docker_cert_dir" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would create $docker_cert_dir and copy certificate"
            return 0
        fi
        mkdir -p "$docker_cert_dir" 2>/dev/null || {
            log_warning "Cannot create $docker_cert_dir (need sudo?)"
            return 0
        }
    fi

    local dest="$docker_cert_dir/enterprise-ca.crt"
    if [[ -f "$dest" ]] && cmp -s "$cert_file" "$dest" 2>/dev/null; then
        log_warning "Docker CA certificate already installed"
    elif [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would copy certificate to $dest"
    else
        cp "$cert_file" "$dest" 2>/dev/null && \
            log_success "Installed Docker CA certificate: $dest" || \
            log_warning "Failed to install Docker CA certificate (need sudo?)"

        log_info "For Docker builds, add to Dockerfile:"
        log_info "  COPY enterprise-ca.crt /usr/local/share/ca-certificates/"
        log_info "  RUN update-ca-certificates"
    fi

    # Copy cert to Docker-accessible location under $HOME
    # (Docker Desktop on macOS cannot bind-mount /Library/Application Support)
    local docker_home_cert="$HOME/.config/netskope"
    mkdir -p "$docker_home_cert" 2>/dev/null
    local src_combined="$NETSKOPE_DATA_PATH/nscacert_combined.pem"
    local src_raw="$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE"
    if [[ -f "$src_combined" ]]; then
        if cmp -s "$src_combined" "$docker_home_cert/nscacert_combined.pem" 2>/dev/null; then
            log_warning "Docker-accessible cert already up to date: $docker_home_cert/"
        elif [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would copy cert to $docker_home_cert/"
        else
            cp "$src_combined" "$docker_home_cert/nscacert_combined.pem"
            log_success "Copied cert to Docker-accessible path: $docker_home_cert/nscacert_combined.pem"
        fi
    fi
    if [[ -f "$src_raw" ]]; then
        cp "$src_raw" "$docker_home_cert/nscacert.pem" 2>/dev/null
    fi

    # Always check/install Docker shell wrapper
    install_docker_hook
}

# ─── Docker Shell Hook Installation ──────────────────────────────────────────

install_docker_hook() {
    local hook_file
    hook_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/netskope-docker-hook.zsh"

    if [[ ! -f "$hook_file" ]]; then
        log_warning "Docker hook not found at: $hook_file"
        return 0
    fi

    local shell_rc=""
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    else
        log_warning "No .zshrc or .bashrc found — cannot install Docker hook"
        return 0
    fi

    # Check if already sourced
    if grep -q "netskope-docker-hook" "$shell_rc" 2>/dev/null; then
        log_warning "Docker shell hook already installed in $shell_rc"
        return 0
    fi

    {
        echo ""
        echo "# Auto-inject Netskope CA certs into Docker containers"
        echo "[[ -f \"$hook_file\" ]] && source \"$hook_file\""
    } >> "$shell_rc"

    log_success "Installed Docker shell hook in $shell_rc"
    log_info "Restart your terminal or run: source $shell_rc"
}

# ─── Rollback ────────────────────────────────────────────────────────────────

rollback_changes() {
    local date_pattern="$1"
    local dry_run="${2:-false}"
    local restored=0

    log_info "Searching for backups matching date: $date_pattern"

    while IFS= read -r -d '' backup; do
        local original="${backup%.backup_*}"
        if [[ "$dry_run" == "true" ]]; then
            log_warning "[DRY-RUN] Would restore: $original from $(basename "$backup")"
        else
            cp "$backup" "$original" 2>/dev/null && {
                log_success "Restored: $original"
                ((restored++)) || true
            } || log_error "Failed to restore: $original"
        fi
    done < <(find / -name "*.backup_${date_pattern}*" -print0 2>/dev/null)

    if [[ $restored -eq 0 ]] && [[ "$dry_run" != "true" ]]; then
        log_warning "No backup files found matching pattern: $date_pattern"
    else
        log_info "Restored $restored file(s)"
    fi
}

# ─── Environment Recommendations ────────────────────────────────────────────

show_env_recommendations() {
    local cert_path="$1"

    [[ "$JSON_OUTPUT" == "true" ]] && return

    echo ""
    log_info "Recommended: Add to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "  # Enterprise SSL certificate configuration"
    echo "  export REQUESTS_CA_BUNDLE=\"$cert_path\""
    echo "  export SSL_CERT_FILE=\"$cert_path\""
    echo "  export NODE_EXTRA_CA_CERTS=\"$cert_path\""
    echo "  export AWS_CA_BUNDLE=\"$cert_path\""
    echo "  export CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE=\"$cert_path\""
    echo ""
}

# ─── Combined Bundle Creation ────────────────────────────────────────────────

create_combined_bundle() {
    local cert_file="$1"
    local combined_path="$NETSKOPE_DATA_PATH/nscacert_combined.pem"

    # Try system cert bundle locations
    local system_bundle=""
    local system_paths=(
        "/etc/ssl/certs/ca-certificates.crt"     # Debian/Ubuntu
        "/etc/pki/tls/certs/ca-bundle.crt"       # RHEL/CentOS
        "/etc/ssl/ca-bundle.pem"                  # openSUSE
        "/usr/local/share/certs/ca-root-nss.crt"  # FreeBSD
        "/etc/ssl/cert.pem"                       # macOS, Alpine
    )

    for p in "${system_paths[@]}"; do
        if [[ -f "$p" ]]; then
            system_bundle="$p"
            break
        fi
    done

    if [[ -n "$system_bundle" ]]; then
        if [[ -f "$combined_path" ]]; then
            log_info "Combined bundle already exists: $combined_path" >&2
        else
            cat "$system_bundle" "$cert_file" > "$combined_path" 2>/dev/null && \
                log_success "Created combined bundle: $combined_path" >&2 || \
                log_warning "Failed to create combined bundle (permission denied?)" >&2
        fi
    fi

    # Return best available cert path (stdout only — logs go to stderr)
    if [[ -f "$combined_path" ]]; then
        echo "$combined_path"
    else
        echo "$cert_file"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    local dry_run=false
    local show_paths=false
    local skip_python=false
    local skip_java=false
    local skip_system=false
    local skip_git=false
    local skip_npm=false
    local skip_pip=false
    local skip_docker=false
    local rollback_date=""
    local parallel=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)       dry_run=true; shift ;;
            -l|--list-paths)    show_paths=true; shift ;;
            --skip-python)      skip_python=true; shift ;;
            --skip-java)        skip_java=true; shift ;;
            --skip-system)      skip_system=true; shift ;;
            --skip-git)         skip_git=true; shift ;;
            --skip-npm)         skip_npm=true; shift ;;
            --skip-pip)         skip_pip=true; shift ;;
            --skip-docker)      skip_docker=true; shift ;;
            --json)             JSON_OUTPUT=true; shift ;;
            --rollback)
                rollback_date="${2:-}"
                if [[ -z "$rollback_date" ]]; then
                    log_error "--rollback requires a date pattern (e.g., 20240115)"
                    exit 1
                fi
                shift 2
                ;;
            --parallel)         parallel=true; shift ;;
            -h|--help)
                cat <<'HELPEOF'
Usage: update-netskope-ca-bundle.sh [OPTIONS]

Updates certificate stores across multiple tools with enterprise SSL
inspection certificates (Netskope, Zscaler, etc.).

Options:
  -n, --dry-run      Preview changes without modifying files
  -l, --list-paths   List search paths and exit
  --skip-python      Skip Python certificate bundle updates
  --skip-java        Skip Java keystore updates
  --skip-system      Skip Linux system CA store update
  --skip-git         Skip git HTTPS configuration
  --skip-npm         Skip npm/yarn/pnpm configuration
  --skip-pip         Skip pip/conda configuration
  --skip-docker      Skip Docker certificate configuration
  --json             Output JSON summary (for CI/CD)
  --rollback DATE    Restore backups from date (YYYYMMDD format)
  --parallel         Update Python cert files in parallel
  -h, --help         Show this help message

Environment Variables:
  NETSKOPE_EXTRA_PATHS   Colon-separated list of additional search paths

Examples:
  ./update-netskope-ca-bundle.sh                    # Update all certificate stores
  ./update-netskope-ca-bundle.sh --dry-run           # Preview changes
  ./update-netskope-ca-bundle.sh --skip-python       # Skip Python bundles
  sudo ./update-netskope-ca-bundle.sh                # Run with elevated permissions
  ./update-netskope-ca-bundle.sh --json              # Machine-readable output
  ./update-netskope-ca-bundle.sh --rollback 20240115 # Restore backups from date
HELPEOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Handle rollback
    if [[ -n "$rollback_date" ]]; then
        print_banner
        rollback_changes "$rollback_date" "$dry_run"
        exit 0
    fi

    print_banner

    if [[ "$show_paths" == "true" ]]; then
        log_info "Search paths:"
        for path in "${SEARCH_PATHS[@]}"; do
            echo "  - $path"
        done
        exit 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "Running in DRY-RUN mode — no changes will be made"
        echo ""
    fi

    # Load enterprise certificate
    log_info "Loading enterprise CA certificate..."
    local netskope_cert
    netskope_cert=$(get_netskope_cert) || exit 1
    log_success "Enterprise CA certificate loaded"

    # Save to temp file
    local temp_cert_file="/tmp/enterprise_cert_$$.pem"
    echo "$netskope_cert" > "$temp_cert_file"
    trap "rm -f '$temp_cert_file'" EXIT

    # Determine the best cert path for tool configuration
    local cert_path="$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE"
    if [[ ! -f "$cert_path" ]]; then
        cert_path="$temp_cert_file"
    fi

    # Try to create combined bundle
    local config_cert_path
    config_cert_path=$(create_combined_bundle "$temp_cert_file")

    # ── Python certificates ──
    if [[ "$skip_python" == "false" ]]; then
        log_info "Searching for Python certificate files..."
        local cert_files
        cert_files=$(find_cacert_files)
        local file_count
        file_count=$(echo "$cert_files" | grep -c . || echo 0)
        log_info "Found $file_count Python certificate file(s)"
        echo ""

        if [[ "$file_count" -gt 0 ]]; then
            log_info "Updating Python certificate files..."
            if [[ "$parallel" == "true" ]] && [[ "$file_count" -gt 4 ]]; then
                log_info "Using parallel mode..."
                echo "$cert_files" | xargs -P 4 -I {} bash -c '
                    file="$1"; cert="$2"; dry="$3"; marker="$4"
                    if grep -q "$marker" "$file" 2>/dev/null; then exit 0; fi
                    if [[ "$dry" == "true" ]]; then exit 0; fi
                    backup="${file}.backup_$(date +%Y%m%d_%H%M%S)"
                    cp "$file" "$backup" 2>/dev/null || exit 1
                    { echo ""; echo "$marker"; echo "# Date: $(date "+%Y-%m-%d %H:%M:%S")"; echo "# Script: enterprise-ca-updater"; echo "$marker"; echo ""; echo "$cert"; } >> "$file"
                ' _ {} "$netskope_cert" "$dry_run" "$MARKER"
                # Recount for summary (approximate in parallel mode)
                log_info "Parallel update complete"
            else
                while IFS= read -r file; do
                    [[ -n "$file" ]] && update_cert_file "$file" "$netskope_cert" "$dry_run"
                done <<< "$cert_files"
            fi
        else
            log_warning "No Python certificate files found in search paths"
        fi
        echo ""
    fi

    # ── Java keystores ──
    if [[ "$skip_java" == "false" ]]; then
        log_info "Searching for Java keystores..."
        local keystore_files
        keystore_files=$(find_cacerts_files)
        local keystore_count
        keystore_count=$(echo "$keystore_files" | grep -c . || echo 0)
        log_info "Found $keystore_count Java keystore(s)"
        echo ""

        if [[ "$keystore_count" -gt 0 ]]; then
            log_info "Updating Java keystores..."
            while IFS= read -r keystore; do
                [[ -n "$keystore" ]] && update_java_keystore "$keystore" "$temp_cert_file" "$dry_run"
            done <<< "$keystore_files"
        else
            log_warning "No Java keystores found"
        fi
        echo ""
    fi

    # ── Linux system CA store ──
    if [[ "$skip_system" == "false" ]]; then
        update_system_ca_store "$temp_cert_file" "$dry_run"
        echo ""
    fi

    # ── Git HTTPS ──
    if [[ "$skip_git" == "false" ]]; then
        update_git_config "$config_cert_path" "$dry_run"
        echo ""
    fi

    # ── npm/yarn/pnpm ──
    if [[ "$skip_npm" == "false" ]]; then
        update_npm_config "$config_cert_path" "$dry_run"
        echo ""
    fi

    # ── pip/conda ──
    if [[ "$skip_pip" == "false" ]]; then
        update_pip_conda_config "$config_cert_path" "$dry_run"
        echo ""
    fi

    # ── Docker ──
    if [[ "$skip_docker" == "false" ]]; then
        update_docker_certs "$temp_cert_file" "$dry_run"
        echo ""
    fi

    print_summary
    show_env_recommendations "$config_cert_path"

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${GREEN}Restart your terminal or applications for changes to take effect.${NC}"
        echo ""
    fi
}

main "$@"
