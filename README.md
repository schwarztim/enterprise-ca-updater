# Netskope PEM Updater

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows-lightgrey.svg)]()

Cross-platform utilities that automatically update Python CA certificate bundles with Netskope SSL inspection certificates.

## The Problem

When Netskope's Secure Web Gateway performs SSL inspection, Python applications encounter SSL verification failures:

```
ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed
requests.exceptions.SSLError: HTTPSConnectionPool(...): certificate verify failed
```

This happens because Python's `certifi` package bundles its own CA certificates, which don't include your organization's Netskope root certificate.

## The Solution

This tool automatically:
1. **Locates** the Netskope CA certificate on your system
2. **Finds** all Python `cacert.pem` files across virtual environments
3. **Appends** the Netskope certificate to each bundle
4. **Configures** environment variables for global SSL certificate resolution
5. **Auto-patches** new virtual environments (macOS)

## Quick Start

### macOS

```bash
# Clone the repository
git clone https://github.com/schwarztim/netskope-pem-updater.git
cd netskope-pem-updater

# Run the updater
./update-netskope-ca-bundle.sh

# Optional: Add auto-patching to your shell
echo 'source /path/to/netskope-pem-updater/netskope-venv-hook.zsh' >> ~/.zshrc
```

### Windows

```powershell
# Clone the repository
git clone https://github.com/schwarztim/netskope-pem-updater.git
cd netskope-pem-updater

# Run as Administrator
.\Update-NetskopeCABundle.ps1
```

---

## macOS Edition

### Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 10.15+ |
| Bash | 4.0+ |
| Netskope Client | Installed |

### Files

| File | Description |
|------|-------------|
| `update-netskope-ca-bundle.sh` | Main script to patch all existing cacert.pem files |
| `netskope-venv-hook.zsh` | Zsh hook to auto-patch new virtual environments |

### Usage

#### Patch All Existing Virtual Environments

```bash
# Preview changes (dry-run)
./update-netskope-ca-bundle.sh --dry-run

# Apply changes
./update-netskope-ca-bundle.sh

# Add extra search paths
NETSKOPE_EXTRA_PATHS='/opt/myapp:/srv/python' ./update-netskope-ca-bundle.sh
```

#### Auto-Patch New Virtual Environments

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Netskope SSL certificate configuration
export REQUESTS_CA_BUNDLE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export SSL_CERT_FILE="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"
export NODE_EXTRA_CA_CERTS="/Library/Application Support/Netskope/STAgent/data/nscacert_combined.pem"

# Auto-patch new venvs with Netskope certs
source /path/to/netskope-pem-updater/netskope-venv-hook.zsh
```

After sourcing, use these commands:

```bash
# Create and auto-patch virtual environment
venv              # Creates .venv with Netskope cert
venv myenv        # Creates myenv with Netskope cert

# For uv users
uvenv             # Creates .venv using uv with Netskope cert

# Manually patch any venv
netskope-patch-venv /path/to/venv
```

#### Command-Line Options

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes without modifying any files |
| `-l, --list-paths` | List search paths and exit |
| `-h, --help` | Show help message |

#### Environment Variables

| Variable | Description |
|----------|-------------|
| `NETSKOPE_EXTRA_PATHS` | Colon-separated list of additional search paths |

### Default Search Paths (macOS)

| Location | Description |
|----------|-------------|
| `$HOME` | User home directory (finds all venvs) |
| `/Library/Frameworks/Python.framework` | Framework Python |
| `/usr/local/lib/python*` | Homebrew Intel Python |
| `/opt/homebrew/lib/python*` | Homebrew Apple Silicon Python |

---

## Windows Edition

### Requirements

| Requirement | Version |
|-------------|---------|
| Windows | 10/11 or Server 2016+ |
| PowerShell | 5.1 or later |
| Privileges | Administrator |

### Usage

```powershell
# Run as Administrator
.\Update-NetskopeCABundle.ps1

# Preview changes
.\Update-NetskopeCABundle.ps1 -DryRun

# Force recreation of the bundle
.\Update-NetskopeCABundle.ps1 -Force
```

### Command-Line Options

| Parameter | Description |
|-----------|-------------|
| `-DryRun` | Preview changes without modifying any files |
| `-Force` | Recreate the certificate bundle even if it exists |
| `-NetskopeDataPath` | Custom path for Netskope data directory |
| `-NetskopeBundle` | Custom name for the certificate bundle file |

### Default Search Paths (Windows)

| Location | Description |
|----------|-------------|
| `C:\Program Files\Python*` | Standard Python installations |
| `%LOCALAPPDATA%\Programs\Python\*` | User Python installations |
| `%ProgramData%\Anaconda*` | Anaconda distributions |
| `%ProgramData%\Miniconda*` | Miniconda distributions |
| `%USERPROFILE%\.conda\envs\*` | Conda virtual environments |
| `%ProgramFiles%\WindowsApps\*Python*` | Windows Store Python |

---

## How It Works

### Certificate Detection

The scripts detect Netskope certificates from:
- **macOS**: `/Library/Application Support/Netskope/STAgent/data/nscacert.pem` or System Keychain
- **Windows**: `%ProgramData%\Netskope\STAgent\data` or Windows Certificate Stores

### Update Process

For each discovered `cacert.pem`:
1. Creates a timestamped backup (`cacert.pem.backup_YYYYMMDD_HHMMSS`)
2. Checks for existing Netskope marker to avoid duplicates
3. Appends Netskope certificate with identification marker
4. Reports success/skip/failure

### Environment Variables

Configure these for global SSL certificate resolution:

| Variable | Used By |
|----------|---------|
| `REQUESTS_CA_BUNDLE` | Python `requests` library |
| `SSL_CERT_FILE` | OpenSSL-based tools |
| `NODE_EXTRA_CA_CERTS` | Node.js |

---

## Troubleshooting

### SSL Errors Persist After Running

1. **Restart your terminal** - Environment variables need a new shell
2. **Verify environment variables**:
   ```bash
   # macOS/Linux
   echo $REQUESTS_CA_BUNDLE

   # Windows
   $env:REQUESTS_CA_BUNDLE
   ```
3. **Re-run the script** to ensure all files are patched
4. **Check Netskope certificate exists**:
   ```bash
   # macOS
   ls -la "/Library/Application Support/Netskope/STAgent/data/nscacert.pem"

   # Windows
   dir "$env:ProgramData\Netskope\STAgent\data\nscacert*.pem"
   ```

### Permission Denied

**macOS**: Some system Python installations require sudo:
```bash
sudo ./update-netskope-ca-bundle.sh
```

**Windows**: Run PowerShell as Administrator

### Reverting Changes

Each updated file has a timestamped backup:
```bash
# Find backups
find . -name "cacert.pem.backup_*"

# Restore specific backup
cp cacert.pem.backup_20240115_143022 cacert.pem
```

### Execution Policy Error (Windows)

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Update-NetskopeCABundle.ps1
```

---

## FAQ

**Q: Will this break my Python installation?**
A: No. The script creates backups before modifying any file and only appends certificates - it doesn't remove existing ones.

**Q: Do I need to run this every time I create a new virtual environment?**
A: If you use the `netskope-venv-hook.zsh`, new venvs are patched automatically. Otherwise, run the script periodically.

**Q: Does this work with conda/anaconda?**
A: Yes, the script searches common conda paths. You may need to add custom paths using `NETSKOPE_EXTRA_PATHS`.

**Q: What if I don't have Netskope installed?**
A: The script will exit gracefully if it can't find the Netskope certificate.

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Tim Schwarz**

---

*This tool is not affiliated with or endorsed by Netskope, Inc.*
