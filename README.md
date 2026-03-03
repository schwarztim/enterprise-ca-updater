# Enterprise Certificate Authority Updater

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

**Formerly:** netskope-pem-updater

Cross-platform utilities that automatically update certificate stores across multiple platforms and languages with enterprise SSL inspection certificates (Netskope, Zscaler, etc.).

## The Problem

When enterprise Secure Web Gateways perform SSL inspection, applications encounter SSL verification failures across multiple platforms:

```
# Python
ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed
requests.exceptions.SSLError: HTTPSConnectionPool(...): certificate verify failed

# Java
sun.security.validator.ValidatorException: PKIX path building failed
javax.net.ssl.SSLHandshakeException: sun.security.provider.certpath.SunCertPathBuilderException

# Node.js
Error: unable to verify the first certificate
FetchError: request to https://... failed, reason: self signed certificate in certificate chain

# Ruby
OpenSSL::SSL::SSLError: SSL_connect returned=1 errno=0 state=error: certificate verify failed
```

This happens because:
- **Python's certifi** bundles its own CA certificates
- **Java** uses isolated keystore files (cacerts)
- **Node.js** has its own CA bundle
- **Ruby/OpenSSL** uses system certificates but may need explicit paths

## The Solution

This tool automatically:
1. **Locates** enterprise CA certificates (Netskope, Zscaler, etc.)
2. **Updates Python** `cacert.pem` files across all virtual environments
3. **Imports certificates** into Java keystores using keytool
4. **Configures** environment variables for Node.js, Ruby, and other tools
5. **Auto-patches** new virtual environments (macOS)

## Supported Certificate Stores

| Platform | Method | Status |
|----------|--------|--------|
| **Python (certifi)** | Append to cacert.pem | ✅ Full Support |
| **Java** | Import to cacerts keystore | ✅ Full Support |
| **Node.js** | NODE_EXTRA_CA_CERTS | ✅ Environment Variable |
| **Ruby/OpenSSL** | SSL_CERT_FILE | ✅ Environment Variable |
| **cURL** | SSL_CERT_FILE | ✅ Environment Variable |
| **Git** | http.sslCAInfo | ⚠️ Manual Config |

## Quick Start

### macOS/Linux

```bash
# Clone the repository
git clone https://github.com/schwarztim/netskope-pem-updater.git
cd netskope-pem-updater

# Make the script executable
chmod +x update-netskope-ca-bundle.sh

# Run the updater (updates both Python and Java)
./update-netskope-ca-bundle.sh

# Only update Java keystores
./update-netskope-ca-bundle.sh --skip-python

# Only update Python bundles
./update-netskope-ca-bundle.sh --skip-java

# Optional: Add auto-patching to your shell
echo 'source /path/to/netskope-pem-updater/netskope-venv-hook.zsh' >> ~/.zshrc
```

### Windows

```powershell
# Clone the repository
git clone https://github.com/schwarztim/netskope-pem-updater.git
cd netskope-pem-updater

# Run as Administrator (updates both Python and Java)
.\Update-NetskopeCABundle.ps1

# Only update Java keystores
.\Update-NetskopeCABundle.ps1 -SkipPython

# Only update Python bundles
.\Update-NetskopeCABundle.ps1 -SkipJava
```

---

## Detailed Documentation

## macOS/Linux Edition

### Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS/Linux | 10.15+ / Any modern distro | |
| Bash | 4.0+ | |
| Enterprise SSL Client | Installed | Netskope, Zscaler, etc. |
| Java (Optional) | 8+ | For Java keystore updates |

### Files

| File | Description |
|------|-------------|
| `update-netskope-ca-bundle.sh` | Main script for all certificate store updates |
| `netskope-venv-hook.zsh` | Zsh hook to auto-patch new Python virtual environments |

### Usage

#### Update All Certificate Stores

```bash
# Make script executable (if needed)
chmod +x update-netskope-ca-bundle.sh

# Preview changes (dry-run)
./update-netskope-ca-bundle.sh --dry-run

# Apply all changes (Python + Java)
./update-netskope-ca-bundle.sh

# Add extra Python search paths
NETSKOPE_EXTRA_PATHS='/opt/myapp:/srv/python' ./update-netskope-ca-bundle.sh
```

#### Command-Line Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes without modifying any files |
| `-l, --list-paths` | List search paths and exit |
| `--skip-python` | Skip Python certificate bundle updates |
| `--skip-java` | Skip Java keystore updates |
| `-h, --help` | Show help message |

#### Environment Variables

| Variable | Description |
|----------|-------------|
| `NETSKOPE_EXTRA_PATHS` | Colon-separated list of additional Python search paths |
| `REQUESTS_CA_BUNDLE` | Python requests library certificate path |
| `SSL_CERT_FILE` | OpenSSL/Ruby certificate path |
| `NODE_EXTRA_CA_CERTS` | Node.js additional CA certificates |

#### Auto-Patch New Virtual Environments

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Enterprise SSL certificate configuration (adapt path to your certificate)
export REQUESTS_CA_BUNDLE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export SSL_CERT_FILE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export NODE_EXTRA_CA_CERTS="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"

# Auto-patch new Python venvs (optional)
source /path/to/netskope-pem-updater/netskope-venv-hook.zsh
```

After sourcing, use these commands:

```bash
# Create and auto-patch virtual environment
venv              # Creates .venv with certificate
venv myenv        # Creates myenv with certificate

# For uv users
uvenv             # Creates .venv using uv with certificate

# Manually patch any venv
netskope-patch-venv /path/to/venv
```

### Default Search Paths

**Python:**
| Location | Description |
|----------|-------------|
| `$HOME` | User home directory (finds all venvs) |
| `/Library/Frameworks/Python.framework` | Framework Python |
| `/usr/local/lib/python*` | Homebrew Intel Python |
| `/opt/homebrew/lib/python*` | Homebrew Apple Silicon Python |

**Java:**
| Location | Description |
|----------|-------------|
| `$JAVA_HOME` | Environment variable Java home |
| `/Library/Java/JavaVirtualMachines/*` | macOS Java installations |
| `/usr/lib/jvm/*` | Linux Java installations |
| `/opt/java/*` | Alternative Linux location |
| `$HOME/.sdkman/candidates/java/*` | SDKMAN Java installations |

---

## Windows Edition

### Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Windows | 10/11 or Server 2016+ | |
| PowerShell | 5.1 or later | |
| Privileges | Administrator | Required for system changes |
| Enterprise SSL Client | Installed | Netskope, Zscaler, etc. |
| Java (Optional) | 8+ | For Java keystore updates |

### Usage

```powershell
# Run as Administrator (all updates)
.\Update-NetskopeCABundle.ps1

# Preview changes
.\Update-NetskopeCABundle.ps1 -DryRun

# Force recreation of the bundle
.\Update-NetskopeCABundle.ps1 -Force

# Only update Java keystores
.\Update-NetskopeCABundle.ps1 -SkipPython

# Only update Python bundles
.\Update-NetskopeCABundle.ps1 -SkipJava
```

### Command-Line Options

| Parameter | Description |
|-----------|-------------|
| `-DryRun` | Preview changes without modifying any files |
| `-Force` | Recreate the certificate bundle even if it exists |
| `-SkipPython` | Skip Python certificate bundle updates |
| `-SkipJava` | Skip Java keystore updates |
| `-NetskopeDataPath` | Custom path for certificate data directory |
| `-NetskopeBundle` | Custom name for the certificate bundle file |

### Default Search Paths

**Python:**
| Location | Description |
|----------|-------------|
| `C:\Program Files\Python*` | Standard Python installations |
| `%LOCALAPPDATA%\Programs\Python\*` | User Python installations |
| `%ProgramData%\Anaconda*` | Anaconda distributions |
| `%ProgramData%\Miniconda*` | Miniconda distributions |
| `%USERPROFILE%\.conda\envs\*` | Conda virtual environments |
| `%ProgramFiles%\WindowsApps\*Python*` | Windows Store Python |

**Java:**
| Location | Description |
|----------|-------------|
| `%JAVA_HOME%` | Environment variable Java home |
| `C:\Program Files\Java\*` | Standard Java installations |
| `C:\Program Files\Eclipse Adoptium\*` | Eclipse Temurin JDK |
| `C:\Program Files\Amazon Corretto\*` | Amazon Corretto JDK |
| `C:\Program Files\Microsoft\*` | Microsoft OpenJDK |
| `%LOCALAPPDATA%\Programs\Eclipse Adoptium\*` | User Eclipse installations |

---

## How It Works

### Certificate Detection

The scripts detect enterprise CA certificates from:
- **macOS**: `/Library/Application Support/Netskope/STAgent/data/nscacert.pem` or System Keychain
- **Windows**: `%ProgramData%\Netskope\STAgent\data` or Windows Certificate Stores
- **Linux**: System certificate stores or custom paths

### Python Update Process

For each discovered `cacert.pem`:
1. Creates a timestamped backup (`cacert.pem.backup_YYYYMMDD_HHMMSS`)
2. Checks for existing certificate marker to avoid duplicates
3. Appends enterprise certificate with identification marker
4. Reports success/skip/failure

### Java Update Process

For each discovered Java keystore (`cacerts`):
1. Creates a timestamped backup (`cacerts.backup_YYYYMMDD_HHMMSS`)
2. Checks if certificate alias already exists
3. Uses `keytool -import` to add certificate to keystore
4. Default password is "changeit" (standard Java keystore password)
5. Reports success/skip/failure

### Environment Variables

Configure these for global SSL certificate resolution:

| Variable | Used By | Platform |
|----------|---------|----------|
| `REQUESTS_CA_BUNDLE` | Python `requests` library | All |
| `SSL_CERT_FILE` | OpenSSL-based tools, Ruby | All |
| `NODE_EXTRA_CA_CERTS` | Node.js | All |
| `AWS_CA_BUNDLE` | AWS CLI | All |
| `CURL_CA_BUNDLE` | cURL | All |

---

## Language-Specific Configuration

### Python

✅ **Automatically handled** by updating `cacert.pem` files

Additional manual config (if needed):
```python
import os
os.environ['REQUESTS_CA_BUNDLE'] = '/path/to/certificate.pem'
```

### Java

✅ **Automatically handled** by importing to cacerts keystore

Verify import:
```bash
keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit -alias netskope-ca
```

### Node.js

✅ **Handled via environment variable** `NODE_EXTRA_CA_CERTS`

Manual per-project config:
```javascript
// In your Node.js application
process.env.NODE_EXTRA_CA_CERTS = '/path/to/certificate.pem';
```

Or via `.npmrc`:
```ini
cafile=/path/to/certificate.pem
```

### Ruby

✅ **Handled via environment variable** `SSL_CERT_FILE`

Manual per-script config:
```ruby
require 'openssl'
OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.set_default_paths
OpenSSL::SSL::SSLContext::DEFAULT_CERT_FILE = '/path/to/certificate.pem'
```

### Go

Manual configuration required:
```bash
# Environment variable
export SSL_CERT_FILE=/path/to/certificate.pem

# Or in Go code
import "crypto/x509"
# Load custom certificate pool
```

### PHP

Manual configuration in `php.ini`:
```ini
curl.cainfo=/path/to/certificate.pem
openssl.cafile=/path/to/certificate.pem
```

### Git

Manual configuration:
```bash
git config --global http.sslCAInfo /path/to/certificate.pem
```

---

## Troubleshooting

### SSL Errors Persist After Running

1. **Restart your terminal** - Environment variables need a new shell
2. **Verify environment variables**:
   ```bash
   # macOS/Linux
   echo $REQUESTS_CA_BUNDLE
   echo $SSL_CERT_FILE
   echo $NODE_EXTRA_CA_CERTS

   # Windows
   $env:REQUESTS_CA_BUNDLE
   $env:SSL_CERT_FILE
   ```
3. **Re-run the script** to ensure all files are patched
4. **Check certificate exists**:
   ```bash
   # macOS
   ls -la "/Library/Application Support/Netskope/STAgent/data/nscacert.pem"

   # Windows
   dir "$env:ProgramData\Netskope\STAgent\data\nscacert*.pem"
   ```

### Java Certificate Not Working

1. **Verify import**:
   ```bash
   keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit | grep netskope
   ```
2. **Check Java version** - Multiple Java versions may have separate keystores
3. **Run script with sudo/admin** if permission denied

### Permission Denied

**macOS/Linux**: Some system files require sudo:
```bash
sudo ./update-netskope-ca-bundle.sh
```

**Windows**: Run PowerShell as Administrator

### Reverting Changes

Each updated file has a timestamped backup:
```bash
# Find backups
find . -name "cacert.pem.backup_*"
find . -name "cacerts.backup_*"

# Restore specific backup
cp cacert.pem.backup_20240115_143022 cacert.pem
cp cacerts.backup_20240115_143022 cacerts
```

### Execution Policy Error (Windows)

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Update-NetskopeCABundle.ps1
```

### keytool Not Found

Ensure Java is installed and in your PATH:
```bash
# Check Java installation
java -version

# Find keytool
which keytool  # macOS/Linux
where keytool  # Windows

# Set JAVA_HOME if needed
export JAVA_HOME=/path/to/java  # macOS/Linux
$env:JAVA_HOME="C:\Program Files\Java\jdk-17"  # Windows
```

---

## FAQ

**Q: Will this break my Python/Java installation?**
A: No. The script creates backups before modifying any file and only appends/imports certificates.

**Q: Do I need to run this every time I create a new virtual environment?**
A: If you use the `netskope-venv-hook.zsh`, new venvs are patched automatically. Otherwise, run the script periodically.

**Q: Does this work with conda/anaconda?**
A: Yes, the script searches common conda paths. You may need to add custom paths using `NETSKOPE_EXTRA_PATHS`.

**Q: What if I don't have Netskope/Zscaler installed?**
A: The script will exit gracefully if it can't find the enterprise certificate.

**Q: Can I use this for other enterprise SSL inspection tools (Zscaler, Blue Coat, etc.)?**
A: Yes! Just modify the `NETSKOPE_DATA_PATH` and `NETSKOPE_CERT_FILE` variables to point to your certificate location.

**Q: Does this work with multiple Java versions?**
A: Yes, the script finds and updates all Java installations on your system.

**Q: Why do I need to update Java keystores separately from Python?**
A: Java uses its own isolated keystore system (cacerts) that is separate from system and Python certificate stores.

**Q: What's the default Java keystore password?**
A: The default password is "changeit" - this is the standard Java keystore password.

---

## Repository Name Change

This repository was renamed from `netskope-pem-updater` to `enterprise-ca-updater` to reflect its broader scope beyond just Netskope certificates. It now supports:
- Multiple enterprise SSL inspection tools (Netskope, Zscaler, etc.)
- Multiple certificate stores (Python, Java)
- Multiple programming languages (Python, Java, Node.js, Ruby, Go, etc.)

**Old URL:** `https://github.com/schwarztim/netskope-pem-updater`
**New URL:** `https://github.com/schwarztim/enterprise-ca-updater`

GitHub automatically redirects the old URL to the new one, but you may want to update your local repository:
```bash
git remote set-url origin https://github.com/schwarztim/enterprise-ca-updater.git
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

### Ideas for Contributions
- Support for additional certificate stores (PostgreSQL, MySQL, etc.)
- Support for additional platforms (Alpine Linux, FreeBSD, etc.)
- Automated testing framework
- Detection and support for additional enterprise SSL inspection tools
- Integration with configuration management tools (Ansible, Puppet, Chef)

---

## References

### Documentation
- [Configuring CLI-based Tools with Netskope](https://community.netskope.com/next-gen-swg-2/configuring-cli-based-tools-and-development-frameworks-to-work-with-netskope-ssl-interception-7015)
- [Java keytool Documentation](https://docs.oracle.com/en/java/javase/11/tools/keytool.html)
- [Node.js Enterprise Network Configuration](https://nodejs.org/en/learn/http/enterprise-network-configuration)
- [Nextstrain CA Certificate Trust Stores](https://docs.nextstrain.org/en/latest/reference/ca-certificates.html)

### Related Tools
- [Python certifi](https://github.com/certifi/python-certifi)
- [node_extra_ca_certs_mozilla_bundle](https://www.npmjs.com/package/node_extra_ca_certs_mozilla_bundle)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Tim Schwarz**

---

*This tool is not affiliated with or endorsed by Netskope, Inc., Zscaler, Inc., or any other enterprise security vendor.*
