#!/bin/bash
#
# update-netskope-ca-bundle.sh - macOS Edition
#
# Updates Python CA certificate bundles with Netskope certificates on macOS.
# Author: Tim Schwarz
# Version: 1.0.0
# Repository: https://github.com/schwarztim/netskope-pem-updater
#

set -euo pipefail

# Configuration
NETSKOPE_DATA_PATH="/Library/Application Support/Netskope/STAgent/data"
NETSKOPE_CERT_FILE="nscacert.pem"
MARKER="# === Netskope CA Bundle Appended ==="

# Default search paths - can be extended via NETSKOPE_EXTRA_PATHS env var
SEARCH_PATHS=(
    "$HOME"
    "/Library/Frameworks/Python.framework"
    "/usr/local/lib/python*"
    "/opt/homebrew/lib/python*"
)

# Add extra paths from environment if set
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

# Logging
log_info()    { echo -e "${NC}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error()   { echo -e "${RED}[ERROR] $1${NC}"; }

print_banner() {
    echo -e "${CYAN}"
    echo "================================================================================"
    echo "                     Netskope Certificate Bundle Updater"
    echo "                              macOS Edition v1.0.0"
    echo "================================================================================"
    echo -e "${NC}"
}

print_summary() {
    echo -e "${CYAN}"
    echo "================================================================================"
    echo "                                  Summary"
    echo "================================================================================"
    echo "    Files Updated:  $UPDATED"
    echo "    Files Skipped:  $SKIPPED"
    echo "    Files Failed:   $FAILED"
    echo "================================================================================"
    echo -e "${NC}"
}

# Get Netskope certificate content
get_netskope_cert() {
    local cert_path="$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE"

    # Try file first
    if [[ -f "$cert_path" ]]; then
        cat "$cert_path"
        return 0
    fi

    # Fallback: export from Keychain
    log_info "Certificate file not found, trying Keychain..."
    local keychain_cert
    keychain_cert=$(security find-certificate -a -c "Netskope" -p /Library/Keychains/System.keychain 2>/dev/null || true)

    if [[ -n "$keychain_cert" ]]; then
        echo "$keychain_cert"
        return 0
    fi

    log_error "Could not find Netskope certificate"
    log_error "Expected location: $cert_path"
    log_error "Ensure Netskope client is installed and running"
    return 1
}

# Check if file already has Netskope cert
has_netskope_cert() {
    local file="$1"
    grep -q "$MARKER" "$file" 2>/dev/null
}

# Find all cacert.pem files
find_cacert_files() {
    local files=()

    for search_path in "${SEARCH_PATHS[@]}"; do
        # Handle glob patterns
        for expanded_path in $search_path; do
            if [[ -d "$expanded_path" ]]; then
                while IFS= read -r -d '' file; do
                    files+=("$file")
                done < <(find "$expanded_path" -name "cacert.pem" -path "*site-packages*certifi*" -print0 2>/dev/null)
            fi
        done
    done

    # Remove duplicates and print
    printf '%s\n' "${files[@]}" | sort -u
}

# Update a single certificate file
update_cert_file() {
    local file="$1"
    local netskope_cert="$2"
    local dry_run="${3:-false}"

    if has_netskope_cert "$file"; then
        log_warning "Skipping (already patched): $file"
        ((SKIPPED++))
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would update: $file"
        return 0
    fi

    # Create backup
    local backup_file="${file}.backup_$(date +%Y%m%d_%H%M%S)"
    if ! cp "$file" "$backup_file" 2>/dev/null; then
        log_error "Failed to backup: $file (permission denied?)"
        ((FAILED++))
        return 1
    fi

    # Append Netskope certificate
    {
        echo ""
        echo "$MARKER"
        echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Script: netskope-pem-updater"
        echo "$MARKER"
        echo ""
        echo "$netskope_cert"
    } >> "$file"

    if [[ $? -eq 0 ]]; then
        log_success "Updated: $file"
        ((UPDATED++))
    else
        log_error "Failed to update: $file"
        mv "$backup_file" "$file" 2>/dev/null
        ((FAILED++))
    fi
}

# Show environment variable recommendations
show_env_recommendations() {
    local combined_bundle="$NETSKOPE_DATA_PATH/nscacert_combined.pem"

    echo ""
    log_info "Recommended: Add to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "  # Netskope SSL certificate configuration"

    if [[ -f "$combined_bundle" ]]; then
        echo "  export REQUESTS_CA_BUNDLE=\"$combined_bundle\""
        echo "  export SSL_CERT_FILE=\"$combined_bundle\""
        echo "  export NODE_EXTRA_CA_CERTS=\"$combined_bundle\""
    else
        echo "  export REQUESTS_CA_BUNDLE=\"$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE\""
        echo "  export SSL_CERT_FILE=\"$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE\""
        echo "  export NODE_EXTRA_CA_CERTS=\"$NETSKOPE_DATA_PATH/$NETSKOPE_CERT_FILE\""
    fi
    echo ""
}

# Main function
main() {
    local dry_run=false
    local show_paths=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -l|--list-paths)
                show_paths=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Updates Python CA certificate bundles with Netskope certificates."
                echo ""
                echo "Options:"
                echo "  -n, --dry-run      Preview changes without modifying files"
                echo "  -l, --list-paths   List search paths and exit"
                echo "  -h, --help         Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  NETSKOPE_EXTRA_PATHS   Colon-separated list of additional search paths"
                echo ""
                echo "Examples:"
                echo "  $0                           # Update all certificate files"
                echo "  $0 --dry-run                 # Preview changes"
                echo "  NETSKOPE_EXTRA_PATHS='/opt/myapp:/srv/python' $0"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    print_banner

    if [[ "$show_paths" == "true" ]]; then
        log_info "Search paths:"
        for path in "${SEARCH_PATHS[@]}"; do
            echo "  - $path"
        done
        exit 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no changes will be made"
        echo ""
    fi

    # Get Netskope certificate
    log_info "Loading Netskope certificate..."
    local netskope_cert
    netskope_cert=$(get_netskope_cert) || exit 1
    log_success "Netskope certificate loaded"

    # Find certificate files
    log_info "Searching for Python certificate files..."
    local cert_files
    cert_files=$(find_cacert_files)
    local file_count
    file_count=$(echo "$cert_files" | grep -c . || echo 0)
    log_info "Found $file_count certificate file(s)"
    echo ""

    if [[ "$file_count" -eq 0 ]]; then
        log_warning "No certificate files found in search paths"
        show_env_recommendations
        exit 0
    fi

    # Update files
    log_info "Updating certificate files..."
    while IFS= read -r file; do
        [[ -n "$file" ]] && update_cert_file "$file" "$netskope_cert" "$dry_run"
    done <<< "$cert_files"

    print_summary
    show_env_recommendations

    echo -e "${GREEN}Restart your terminal or applications for changes to take effect.${NC}"
    echo ""
}

main "$@"
