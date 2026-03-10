# toolhive-secrets-hook.zsh
# Loads toolhive secrets from secure-tools keychain into TOOLHIVE_SECRET_* env vars.
# Source from ~/.zshrc BEFORE any thv commands.
#
# Secrets are stored as:
#   service: toolhive-secret
#   account: <SECRET_NAME>
#   password: <secret value>

_THV_KC="$HOME/Library/Keychains/secure-tools.keychain-db"

_thv_load_secret() {
    local name="$1"
    local val
    val=$(security find-generic-password -s "toolhive-secret" -a "$name" -w "$_THV_KC" 2>/dev/null) || return 1
    export "TOOLHIVE_SECRET_${name}=${val}"
}

# Load all known toolhive secrets
_thv_secrets=(
    AKAMAI_ACCESS_TOKEN
    AKAMAI_CLIENT_SECRET
    AKAMAI_CLIENT_TOKEN
    AKAMAI_HOST
    VENAFI_BASE_URL
    EPM_PASSWORD
    EPM_USERNAME
)

for _s in "${_thv_secrets[@]}"; do
    _thv_load_secret "$_s"
done
unset _s _thv_secrets
