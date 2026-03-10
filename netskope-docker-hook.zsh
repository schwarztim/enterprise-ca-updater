# netskope-docker-hook.zsh
# Transparent Docker wrapper that injects Netskope CA certificates
# into every `docker run`, `docker build`, and `docker compose` invocation.
#
# Installation: Add to ~/.zshrc:
#   source /path/to/netskope-docker-hook.zsh
#
# Repository: https://github.com/schwarztim/enterprise-ca-updater
#

# Use Docker-accessible copy under $HOME (Docker Desktop on macOS cannot bind-mount
# /Library/Application Support). The cert is synced there by update-netskope-ca-bundle.sh.
# Fall back to system paths on Linux where Docker has full host access.
if [[ -f "$HOME/.config/netskope/nscacert_combined.pem" ]]; then
    _NETSKOPE_DOCKER_CERT="$HOME/.config/netskope/nscacert_combined.pem"
elif [[ -f "$HOME/.config/netskope/nscacert.pem" ]]; then
    _NETSKOPE_DOCKER_CERT="$HOME/.config/netskope/nscacert.pem"
elif [[ -f "/opt/netskope/data/nscacert.pem" ]]; then
    _NETSKOPE_DOCKER_CERT="/opt/netskope/data/nscacert.pem"
elif [[ -f "/etc/netskope/nscacert.pem" ]]; then
    _NETSKOPE_DOCKER_CERT="/etc/netskope/nscacert.pem"
else
    _NETSKOPE_DOCKER_CERT=""
fi

_NETSKOPE_CONTAINER_CERT_PATH="/etc/ssl/certs/netskope-ca.crt"

docker() {
    # Pass through if no cert found
    if [[ -z "$_NETSKOPE_DOCKER_CERT" ]]; then
        command docker "$@"
        return
    fi

    case "$1" in
        run)
            shift
            _netskope_docker_run "$@"
            ;;
        build)
            shift
            _netskope_docker_build "$@"
            ;;
        compose)
            shift
            _netskope_docker_compose "$@"
            ;;
        *)
            command docker "$@"
            ;;
    esac
}

_netskope_docker_run() {
    local args=()
    local has_netskope_vol=false

    # Check if user already added the netskope cert volume
    for arg in "$@"; do
        if [[ "$arg" == *"netskope"*":"*"/etc/ssl"* ]] || \
           [[ "$arg" == *"nscacert"*":"* ]]; then
            has_netskope_vol=true
            break
        fi
    done

    if [[ "$has_netskope_vol" == false ]]; then
        args+=(
            -v "${_NETSKOPE_DOCKER_CERT}:${_NETSKOPE_CONTAINER_CERT_PATH}:ro"
            -e "SSL_CERT_FILE=${_NETSKOPE_CONTAINER_CERT_PATH}"
            -e "NODE_EXTRA_CA_CERTS=${_NETSKOPE_CONTAINER_CERT_PATH}"
            -e "REQUESTS_CA_BUNDLE=${_NETSKOPE_CONTAINER_CERT_PATH}"
        )
    fi

    command docker run "${args[@]}" "$@"
}

_netskope_docker_build() {
    local args=()
    local has_netskope_arg=false

    # Check if user already passed the NETSKOPE_CERT build arg
    for arg in "$@"; do
        if [[ "$arg" == *"NETSKOPE_CERT"* ]]; then
            has_netskope_arg=true
            break
        fi
    done

    if [[ "$has_netskope_arg" == false ]]; then
        args+=(--build-arg "NETSKOPE_CERT=$(cat "$_NETSKOPE_DOCKER_CERT")")
    fi

    command docker build "${args[@]}" "$@"
}

_netskope_docker_compose() {
    case "$1" in
        run)
            shift
            _netskope_docker_compose_run "$@"
            ;;
        exec)
            # exec attaches to existing container, no injection needed
            command docker compose exec "$@"
            ;;
        *)
            command docker compose "$@"
            ;;
    esac
}

_netskope_docker_compose_run() {
    local args=()
    local has_netskope_vol=false

    for arg in "$@"; do
        if [[ "$arg" == *"netskope"* ]] || [[ "$arg" == *"nscacert"* ]]; then
            has_netskope_vol=true
            break
        fi
    done

    if [[ "$has_netskope_vol" == false ]]; then
        args+=(
            -v "${_NETSKOPE_DOCKER_CERT}:${_NETSKOPE_CONTAINER_CERT_PATH}:ro"
            -e "SSL_CERT_FILE=${_NETSKOPE_CONTAINER_CERT_PATH}"
            -e "NODE_EXTRA_CA_CERTS=${_NETSKOPE_CONTAINER_CERT_PATH}"
            -e "REQUESTS_CA_BUNDLE=${_NETSKOPE_CONTAINER_CERT_PATH}"
        )
    fi

    command docker compose run "${args[@]}" "$@"
}

# Disable the wrapper (escape hatch)
docker-no-netskope() {
    command docker "$@"
}
