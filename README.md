# Enterprise Certificate Authority Updater

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

**Formerly:** netskope-pem-updater

Cross-platform tool that automatically updates certificate stores across multiple platforms, languages, and developer tools with enterprise SSL inspection certificates (Netskope, Zscaler, etc.).

## The Problem

When enterprise Secure Web Gateways perform SSL inspection, applications encounter SSL verification failures:

```
# Python
ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED]

# Java
sun.security.validator.ValidatorException: PKIX path building failed

# Node.js
Error: unable to verify the first certificate

# Git
fatal: unable to access 'https://...': SSL certificate problem

# npm
npm ERR! code UNABLE_TO_VERIFY_LEAF_SIGNATURE

# pip
pip._vendor.urllib3.exceptions.SSLError: [SSL: CERTIFICATE_VERIFY_FAILED]
```

## The Solution

This tool automatically:

1. **Locates** enterprise CA certificates (Netskope, Zscaler, etc.)
2. **Updates Python** `cacert.pem` files across all virtual environments
3. **Imports certificates** into Java keystores
4. **Configures** git, npm/yarn/pnpm, pip/conda for SSL trust
5. **Updates** Linux system CA stores (Debian, RHEL, Arch)
6. **Installs** Docker daemon certificates
7. **Recommends** environment variables for Node.js, Ruby, AWS CLI, gcloud, and more
8. **Auto-patches** new virtual environments (macOS zsh hook)

## Supported Certificate Stores

| Target                   | Method                                            | Status               |
| ------------------------ | ------------------------------------------------- | -------------------- |
| **Python (certifi)**     | Append to cacert.pem                              | Automatic            |
| **Java**                 | Import to cacerts keystore                        | Automatic            |
| **Linux System CA**      | update-ca-certificates / update-ca-trust          | Automatic            |
| **Git**                  | `git config --global http.sslCAInfo`              | Automatic            |
| **npm/yarn/pnpm**        | `.npmrc` cafile                                   | Automatic            |
| **pip**                  | `pip config set global.cert`                      | Automatic            |
| **conda**                | `conda config --set ssl_verify`                   | Automatic            |
| **Docker**               | Copy to `/etc/docker/certs.d/`                    | Automatic            |
| **Node.js**              | `NODE_EXTRA_CA_CERTS`                             | Environment Variable |
| **Ruby/OpenSSL**         | `SSL_CERT_FILE`                                   | Environment Variable |
| **cURL**                 | `SSL_CERT_FILE`                                   | Environment Variable |
| **AWS CLI**              | `AWS_CA_BUNDLE`                                   | Environment Variable |
| **gcloud**               | `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE`              | Environment Variable |
| **Windows System Store** | `Import-Certificate` to `Cert:\LocalMachine\Root` | Automatic (PS)       |
| **WSL**                  | Detects distros, runs `update-ca-certificates`    | Automatic (PS)       |

## Quick Start

### macOS/Linux

```bash
git clone https://github.com/schwarztim/enterprise-ca-updater.git
cd enterprise-ca-updater

chmod +x update-netskope-ca-bundle.sh

# Preview what will change
./update-netskope-ca-bundle.sh --dry-run

# Update everything
sudo ./update-netskope-ca-bundle.sh

# Selective updates
./update-netskope-ca-bundle.sh --skip-python --skip-java    # Only git/npm/pip/docker
./update-netskope-ca-bundle.sh --skip-git --skip-npm         # Only Python/Java

# CI/CD integration
./update-netskope-ca-bundle.sh --json

# Auto-patch new Python venvs
echo 'source /path/to/enterprise-ca-updater/netskope-venv-hook.zsh' >> ~/.zshrc
```

### Windows

```powershell
git clone https://github.com/schwarztim/enterprise-ca-updater.git
cd enterprise-ca-updater

# Run as Administrator
.\Update-NetskopeCABundle.ps1

# Preview changes
.\Update-NetskopeCABundle.ps1 -DryRun

# Selective updates
.\Update-NetskopeCABundle.ps1 -SkipPython -SkipJava
.\Update-NetskopeCABundle.ps1 -SkipGit -SkipNpm

# JSON output for automation
.\Update-NetskopeCABundle.ps1 -Json

# Rollback changes from a specific date
.\Update-NetskopeCABundle.ps1 -Rollback 20260301
```

---

## Command-Line Reference

### macOS/Linux (`update-netskope-ca-bundle.sh`)

| Option             | Description                             |
| ------------------ | --------------------------------------- |
| `-n, --dry-run`    | Preview changes without modifying files |
| `-l, --list-paths` | List search paths and exit              |
| `--skip-python`    | Skip Python certificate bundle updates  |
| `--skip-java`      | Skip Java keystore updates              |
| `--skip-system`    | Skip Linux system CA store update       |
| `--skip-git`       | Skip git HTTPS configuration            |
| `--skip-npm`       | Skip npm/yarn/pnpm configuration        |
| `--skip-pip`       | Skip pip/conda configuration            |
| `--skip-docker`    | Skip Docker certificate configuration   |
| `--json`           | Output JSON summary (for CI/CD)         |
| `--rollback DATE`  | Restore backups from date (YYYYMMDD)    |
| `--parallel`       | Update Python cert files in parallel    |
| `-h, --help`       | Show help message                       |

### Windows (`Update-NetskopeCABundle.ps1`)

| Parameter           | Description                             |
| ------------------- | --------------------------------------- |
| `-DryRun`           | Preview changes without modifying files |
| `-Force`            | Recreate the certificate bundle         |
| `-SkipPython`       | Skip Python certificate bundle updates  |
| `-SkipJava`         | Skip Java keystore updates              |
| `-SkipSystem`       | Skip Windows system store injection     |
| `-SkipGit`          | Skip git HTTPS configuration            |
| `-SkipNpm`          | Skip npm/yarn/pnpm configuration        |
| `-SkipPip`          | Skip pip/conda configuration            |
| `-SkipDocker`       | Skip Docker certificate configuration   |
| `-Json`             | Output JSON summary                     |
| `-Rollback DATE`    | Restore backups from date (YYYYMMDD)    |
| `-NetskopeDataPath` | Custom certificate data directory       |
| `-NetskopeBundle`   | Custom certificate bundle filename      |

### Environment Variables

| Variable                             | Used By                         | Platform    |
| ------------------------------------ | ------------------------------- | ----------- |
| `REQUESTS_CA_BUNDLE`                 | Python `requests`               | All         |
| `SSL_CERT_FILE`                      | OpenSSL, Ruby, cURL             | All         |
| `NODE_EXTRA_CA_CERTS`                | Node.js                         | All         |
| `AWS_CA_BUNDLE`                      | AWS CLI                         | All         |
| `CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE` | gcloud                          | All         |
| `CURL_CA_BUNDLE`                     | cURL                            | All         |
| `NETSKOPE_EXTRA_PATHS`               | Script: additional search paths | macOS/Linux |

---

## How It Works

### Certificate Detection

| Platform    | Locations Checked                                                                  |
| ----------- | ---------------------------------------------------------------------------------- |
| **macOS**   | `/Library/Application Support/Netskope/STAgent/data/nscacert.pem`, System Keychain |
| **Windows** | `%ProgramData%\Netskope\STAgent\data`, Windows Certificate Stores                  |
| **Linux**   | `/opt/netskope/`, `/etc/netskope/`, `/opt/zscaler/`, system CA dirs                |

### Update Process

**Python:** Creates timestamped backup, checks for existing marker, appends enterprise cert with identification marker.

**Java:** Creates timestamped backup, checks alias existence, imports via `keytool -import`.

**Git/npm/pip/conda:** Checks current config, skips if already set, applies global configuration.

**Linux System CA:** Detects distro (`update-ca-certificates` vs `update-ca-trust` vs `trust anchor`), copies cert to appropriate directory.

**Docker:** Copies cert to `/etc/docker/certs.d/`, provides Dockerfile guidance.

**Windows System Store (PS):** Uses `Import-Certificate` to add to `Cert:\LocalMachine\Root`.

**WSL (PS):** Detects installed distros, copies cert into each, runs appropriate update command.

### Rollback

Every modified file gets a timestamped backup. Use `--rollback YYYYMMDD` to restore all backups from a given date:

```bash
# Restore all changes from March 1, 2026
./update-netskope-ca-bundle.sh --rollback 20260301

# Preview what would be restored
./update-netskope-ca-bundle.sh --rollback 20260301 --dry-run
```

### JSON Output

For CI/CD integration, use `--json` to get machine-readable output:

```json
{
  "version": "2.0.0",
  "timestamp": "2026-03-03T12:00:00Z",
  "stats": {
    "python": { "updated": 5, "skipped": 2, "failed": 0 },
    "java": { "updated": 1, "skipped": 0, "failed": 0 },
    "git": { "updated": 1 },
    "npm": { "updated": 1 },
    "pip": { "updated": 1 },
    "system": { "updated": 0 }
  }
}
```

---

## Auto-Patch Virtual Environments

Add to your `~/.zshrc`:

```bash
# Enterprise SSL certificate configuration
export REQUESTS_CA_BUNDLE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export SSL_CERT_FILE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export NODE_EXTRA_CA_CERTS="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"

# Auto-patch new Python venvs
source /path/to/enterprise-ca-updater/netskope-venv-hook.zsh
```

Commands:

```bash
venv              # Creates .venv with certificate patching
venv myenv        # Creates named venv with certificate patching
uvenv             # Creates .venv using uv with certificate patching
netskope-patch-venv /path/to/venv   # Manually patch any venv
```

---

## Docker Integration

The script installs the certificate for Docker daemon registry trust **and** a transparent shell wrapper that auto-injects the certificate into every container.

### Automatic Container Injection (Shell Wrapper)

The `netskope-docker-hook.zsh` wraps the `docker` command to transparently inject the Netskope CA certificate into every container:

```bash
# Installed automatically by update-netskope-ca-bundle.sh, or manually:
source /path/to/enterprise-ca-updater/netskope-docker-hook.zsh
```

What gets injected:

| Command              | Injection                                                                            |
| -------------------- | ------------------------------------------------------------------------------------ |
| `docker run`         | Volume mount + `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE` env vars |
| `docker build`       | `--build-arg NETSKOPE_CERT=<cert contents>`                                          |
| `docker compose run` | Volume mount + env vars (same as `docker run`)                                       |

The wrapper is idempotent — if you already pass a netskope cert volume or build arg, it won't duplicate it.

To bypass the wrapper for a single command:

```bash
docker-no-netskope run alpine wget https://example.com
```

### Dockerfile Usage

For `docker build`, the cert is available as the `NETSKOPE_CERT` build arg:

```dockerfile
ARG NETSKOPE_CERT=""
RUN if [ -n "$NETSKOPE_CERT" ]; then \
      echo "$NETSKOPE_CERT" > /usr/local/share/ca-certificates/netskope.crt && \
      update-ca-certificates; \
    fi
```

### Manual Docker Daemon Certs

The script also copies the certificate to `/etc/docker/certs.d/` for Docker daemon registry trust.

---

## Troubleshooting

### SSL Errors Persist After Running

1. **Restart your terminal** — environment variables need a new shell
2. **Verify environment variables**: `echo $REQUESTS_CA_BUNDLE`
3. **Re-run the script** to ensure all files are patched
4. **Check certificate exists**: `ls -la "/Library/Application Support/Netskope/STAgent/data/nscacert.pem"`

### Permission Denied

```bash
# macOS/Linux — run with sudo
sudo ./update-netskope-ca-bundle.sh

# Windows — run PowerShell as Administrator
```

### Java Certificate Not Working

```bash
keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit | grep netskope
```

Multiple Java versions may have separate keystores — the script finds and updates all of them.

### Reverting Changes

```bash
# Find all backups
find / -name "*.backup_*" 2>/dev/null | head -20

# Restore from a specific date
./update-netskope-ca-bundle.sh --rollback 20260301
```

---

## FAQ

**Q: Will this break my installations?**
A: No. The script creates backups before every modification and only appends/imports certificates.

**Q: Do I need to run this every time I create a new virtual environment?**
A: Use `netskope-venv-hook.zsh` to auto-patch new venvs. Otherwise, run periodically.

**Q: Does this work with conda/anaconda?**
A: Yes. It searches common conda paths and configures `conda config --set ssl_verify`.

**Q: Can I use this for other SSL inspection tools (Zscaler, Blue Coat)?**
A: Yes. Modify `NETSKOPE_DATA_PATH` and `NETSKOPE_CERT_FILE`, or place your cert in a detected location.

**Q: Does this work with multiple Java versions?**
A: Yes. All Java installations are discovered and updated.

---

## Repository Name Change

This repository was renamed from `netskope-pem-updater` to `enterprise-ca-updater` to reflect its broader scope. GitHub automatically redirects the old URL.

```bash
git remote set-url origin https://github.com/schwarztim/enterprise-ca-updater.git
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

### Ideas for Contributions

- Support for additional certificate stores (PostgreSQL, MySQL, etc.)
- Support for additional platforms (Alpine Linux, FreeBSD, etc.)
- Automated testing framework
- Integration with configuration management tools (Ansible, Puppet, Chef)
- Homebrew tap for easy installation

---

## References

- [Configuring CLI-based Tools with Netskope](https://community.netskope.com/next-gen-swg-2/configuring-cli-based-tools-and-development-frameworks-to-work-with-netskope-ssl-interception-7015)
- [Java keytool Documentation](https://docs.oracle.com/en/java/javase/11/tools/keytool.html)
- [Node.js Enterprise Network Configuration](https://nodejs.org/en/learn/http/enterprise-network-configuration)
- [Nextstrain CA Certificate Trust Stores](https://docs.nextstrain.org/en/latest/reference/ca-certificates.html)
- [Python certifi](https://github.com/certifi/python-certifi)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Tim Schwarz**

---

_This tool is not affiliated with or endorsed by Netskope, Inc., Zscaler, Inc., or any other enterprise security vendor._
