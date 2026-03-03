#!/bin/bash
#
# update-netskope-ca-bundle.sh - macOS/Linux Edition
#
# Updates Python CA certificate bundles and Java keystores with Netskope certificates.
# Author: Tim Schwarz
# Version: 2.0.0
# Repository: https://github.com/schwarztim/netskope-pem-updater
#

set -euo pipefail

# Configuration
NETSKOPE_DATA_PATH="/Library/Application Support/Netskope/STAgent/data"
NETSKOPE_CERT_FILE="nscacert.pem"
MARKER="# === Netskope CA Bundle Appended ==="
JAVA_KEYSTORE_PASSWORD="changeit"  # Default Java keystore password
NETSKOPE_ALIAS="netskope-ca"

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
JAVA_UPDATED=0
JAVA_SKIPPED=0
JAVA_FAILED=0

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
    echo "    Python Bundles Updated:  $UPDATED"
    echo "    Python Bundles Skipped:  $SKIPPED"
    echo "    Python Bundles Failed:   $FAILED"
    echo "    Java Keystores Updated:  $JAVA_UPDATED"
    echo "    Java Keystores Skipped:  $JAVA_SKIPPED"
    echo "    Java Keystores Failed:   $JAVA_FAILED"
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

# Find Java installations
find_java_installations() {
    local java_homes=()

    # Check JAVA_HOME environment variable
    if [[ -n "${JAVA_HOME:-}" ]] && [[ -d "$JAVA_HOME" ]]; then
        java_homes+=("$JAVA_HOME")
    fi

    # Common Java installation locations
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

    # Remove duplicates and print
    printf '%s\n' "${java_homes[@]}" | sort -u
}

# Find cacerts keystore files
find_cacerts_files() {
    local cacerts_files=()
    local java_homes

    java_homes=$(find_java_installations)

    while IFS= read -r java_home; do
        [[ -z "$java_home" ]] && continue

        # Check common locations within Java installation
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

    # Also check system-wide locations
    local system_locations=(
        "/etc/ssl/certs/java/cacerts"
        "/etc/pki/java/cacerts"
    )

    for cacerts_path in "${system_locations[@]}"; do
        if [[ -f "$cacerts_path" ]]; then
            cacerts_files+=("$cacerts_path")
        fi
    done

    # Remove duplicates and print
    printf '%s\n' "${cacerts_files[@]}" | sort -u
}

# Check if Java keystore already has Netskope certificate
has_netskope_in_keystore() {
    local keystore="$1"
    local keytool_cmd

    # Find keytool command
    if command -v keytool &> /dev/null; then
        keytool_cmd="keytool"
    else
        # Try to find keytool relative to the keystore
        local java_home
        java_home=$(dirname "$(dirname "$(dirname "$keystore")")")
        if [[ -f "$java_home/bin/keytool" ]]; then
            keytool_cmd="$java_home/bin/keytool"
        else
            log_error "keytool command not found for $keystore"
            return 1
        fi
    fi

    # Check if alias exists in keystore
    "$keytool_cmd" -list -keystore "$keystore" -storepass "$JAVA_KEYSTORE_PASSWORD" -alias "$NETSKOPE_ALIAS" &>/dev/null
}

# Update Java keystore with Netskope certificate
update_java_keystore() {
    local keystore="$1"
    local cert_file="$2"
    local dry_run="${3:-false}"
    local keytool_cmd

    # Find keytool command
    if command -v keytool &> /dev/null; then
        keytool_cmd="keytool"
    else
        local java_home
        java_home=$(dirname "$(dirname "$(dirname "$keystore")")")
        if [[ -f "$java_home/bin/keytool" ]]; then
            keytool_cmd="$java_home/bin/keytool"
        else
            log_error "keytool command not found for $keystore"
            ((JAVA_FAILED++))
            return 1
        fi
    fi

    # Check if already present
    if has_netskope_in_keystore "$keystore"; then
        log_warning "Skipping (already present): $keystore"
        ((JAVA_SKIPPED++))
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_warning "[DRY-RUN] Would update keystore: $keystore"
        return 0
    fi

    # Create backup
    local backup_file="${keystore}.backup_$(date +%Y%m%d_%H%M%S)"
    if ! cp "$keystore" "$backup_file" 2>/dev/null; then
        log_error "Failed to backup: $keystore (permission denied?)"
        ((JAVA_FAILED++))
        return 1
    fi

    # Import certificate
    if "$keytool_cmd" -import -noprompt -trustcacerts \
        -alias "$NETSKOPE_ALIAS" \
        -file "$cert_file" \
        -keystore "$keystore" \
        -storepass "$JAVA_KEYSTORE_PASSWORD" &>/dev/null; then
        log_success "Updated Java keystore: $keystore"
        ((JAVA_UPDATED++))
    else
        log_error "Failed to update keystore: $keystore"
        mv "$backup_file" "$keystore" 2>/dev/null
        ((JAVA_FAILED++))
    fi
}

# Main function
main() {
    local dry_run=false
    local show_paths=false
    local skip_python=false
    local skip_java=false

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
            --skip-python)
                skip_python=true
                shift
                ;;
            --skip-java)
                skip_java=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Updates Python CA certificate bundles and Java keystores with Netskope certificates."
                echo ""
                echo "Options:"
                echo "  -n, --dry-run      Preview changes without modifying files"
                echo "  -l, --list-paths   List search paths and exit"
                echo "  --skip-python      Skip Python certificate bundle updates"
                echo "  --skip-java        Skip Java keystore updates"
                echo "  -h, --help         Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  NETSKOPE_EXTRA_PATHS   Colon-separated list of additional search paths"
                echo ""
                echo "Examples:"
                echo "  $0                           # Update all certificate stores"
                echo "  $0 --dry-run                 # Preview changes"
                echo "  $0 --skip-python             # Only update Java keystores"
                echo "  $0 --skip-java               # Only update Python bundles"
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

    # Save certificate to temporary file for Java import
    local temp_cert_file="/tmp/netskope_cert_$$.pem"
    echo "$netskope_cert" > "$temp_cert_file"

    # Update Python certificates
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
            while IFS= read -r file; do
                [[ -n "$file" ]] && update_cert_file "$file" "$netskope_cert" "$dry_run"
            done <<< "$cert_files"
        else
            log_warning "No Python certificate files found in search paths"
        fi
        echo ""
    fi

    # Update Java keystores
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

    # Cleanup
    rm -f "$temp_cert_file"

    print_summary
    show_env_recommendations

    echo -e "${GREEN}Restart your terminal or applications for changes to take effect.${NC}"
    echo ""
}

main "$@"
