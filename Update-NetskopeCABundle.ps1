#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Updates Python CA certificate bundles and Java keystores with Netskope certificates on Windows.

.DESCRIPTION
    This script:
    1. Locates or creates the Netskope certificate bundle
    2. Finds all Python cacert.pem files on the system
    3. Appends the Netskope certificates to each Python bundle
    4. Finds all Java cacerts keystores on the system
    5. Imports Netskope certificates into each Java keystore
    6. Sets environment variables for SSL certificate resolution

.PARAMETER NetskopeDataPath
    Path to the Netskope data directory. Defaults to %ProgramData%\Netskope\STAgent\data

.PARAMETER NetskopeBundle
    Name of the Netskope certificate bundle file. Defaults to nscacert_combined.pem

.PARAMETER DryRun
    Preview changes without modifying any files.

.PARAMETER Force
    Recreate the Netskope bundle even if it already exists.

.PARAMETER SkipPython
    Skip Python certificate bundle updates.

.PARAMETER SkipJava
    Skip Java keystore updates.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1
    Runs the script with default settings.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1 -DryRun
    Preview what changes would be made without modifying files.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1 -Force
    Force recreation of the Netskope certificate bundle.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1 -SkipPython
    Only update Java keystores, skip Python bundles.

.NOTES
    Author: Tim Schwarz
    Version: 2.0.0
    Requires: PowerShell 5.1+, Administrator privileges, Java (for keystore updates)
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Path to Netskope data directory")]
    [string]$NetskopeDataPath = "$env:ProgramData\Netskope\STAgent\data",

    [Parameter(HelpMessage = "Name of the certificate bundle file")]
    [string]$NetskopeBundle = "nscacert_combined.pem",

    [Parameter(HelpMessage = "Preview changes without modifying files")]
    [switch]$DryRun,

    [Parameter(HelpMessage = "Force recreation of the bundle")]
    [switch]$Force,

    [Parameter(HelpMessage = "Skip Python certificate bundle updates")]
    [switch]$SkipPython,

    [Parameter(HelpMessage = "Skip Java keystore updates")]
    [switch]$SkipJava
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script-level variables
$script:UpdateLog = [System.Collections.ArrayList]::new()
$script:Stats = @{
    PythonUpdated = 0
    PythonSkipped = 0
    PythonFailed  = 0
    JavaUpdated   = 0
    JavaSkipped   = 0
    JavaFailed    = 0
}
$script:JavaKeystorePassword = "changeit"  # Default Java keystore password
$script:NetskopeAlias = "netskope-ca"

#region Logging Functions

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    [void]$script:UpdateLog.Add($logEntry)

    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}

function Write-Banner {
    $banner = @"

================================================================================
                     Netskope Certificate Bundle Updater
                              Windows Edition
================================================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Summary {
    $summary = @"

================================================================================
                                  Summary
================================================================================
    Python Bundles Updated:  $($script:Stats.PythonUpdated)
    Python Bundles Skipped:  $($script:Stats.PythonSkipped)
    Python Bundles Failed:   $($script:Stats.PythonFailed)
    Java Keystores Updated:  $($script:Stats.JavaUpdated)
    Java Keystores Skipped:  $($script:Stats.JavaSkipped)
    Java Keystores Failed:   $($script:Stats.JavaFailed)
================================================================================

"@
    Write-Host $summary -ForegroundColor Cyan
}

#endregion

#region Certificate Functions

function Export-WindowsRootCertificates {
    <#
    .SYNOPSIS
        Exports trusted root certificates from Windows certificate stores to PEM format.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Write-Log "Exporting Windows trusted root certificates..."

    $pemBuilder = [System.Text.StringBuilder]::new()
    $stores = @(
        @{ Location = "LocalMachine"; Name = "Root" },
        @{ Location = "LocalMachine"; Name = "CA" }
    )

    $exportCount = 0

    foreach ($store in $stores) {
        $storePath = "Cert:\$($store.Location)\$($store.Name)"

        try {
            $certificates = Get-ChildItem -Path $storePath -ErrorAction Stop

            foreach ($cert in $certificates) {
                if (-not $cert.HasPrivateKey) {
                    $base64 = [Convert]::ToBase64String(
                        $cert.RawData,
                        [Base64FormattingOptions]::InsertLineBreaks
                    )

                    [void]$pemBuilder.AppendLine("# Subject: $($cert.Subject)")
                    [void]$pemBuilder.AppendLine("# Issuer: $($cert.Issuer)")
                    [void]$pemBuilder.AppendLine("# Thumbprint: $($cert.Thumbprint)")
                    [void]$pemBuilder.AppendLine("-----BEGIN CERTIFICATE-----")
                    [void]$pemBuilder.AppendLine($base64)
                    [void]$pemBuilder.AppendLine("-----END CERTIFICATE-----")
                    [void]$pemBuilder.AppendLine()

                    $exportCount++
                }
            }
        }
        catch {
            Write-Log "Failed to read certificate store $storePath`: $_" -Level WARNING
        }
    }

    Write-Log "Exported $exportCount certificates from Windows certificate stores"
    return $pemBuilder.ToString()
}

function Initialize-NetskopeBundle {
    <#
    .SYNOPSIS
        Creates or validates the Netskope certificate bundle.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $bundlePath = Join-Path -Path $NetskopeDataPath -ChildPath $NetskopeBundle

    # Ensure directory exists
    if (-not (Test-Path -Path $NetskopeDataPath -PathType Container)) {
        Write-Log "Creating Netskope data directory: $NetskopeDataPath"

        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $NetskopeDataPath -Force | Out-Null
        }
    }

    # Check if bundle already exists
    if ((Test-Path -Path $bundlePath -PathType Leaf) -and -not $Force) {
        Write-Log "Netskope certificate bundle exists: $bundlePath"
        return $bundlePath
    }

    Write-Log "Creating Netskope certificate bundle..."

    if (-not $DryRun) {
        $pemContent = Export-WindowsRootCertificates
        $pemContent | Out-File -FilePath $bundlePath -Encoding UTF8 -Force

        if (Test-Path -Path $bundlePath -PathType Leaf) {
            Write-Log "Successfully created certificate bundle" -Level SUCCESS
        }
        else {
            throw "Failed to create certificate bundle at $bundlePath"
        }
    }
    else {
        Write-Log "[DRY-RUN] Would create certificate bundle at $bundlePath" -Level WARNING
    }

    return $bundlePath
}

#endregion

#region Python Certificate Discovery

function Find-PythonCertificateFiles {
    <#
    .SYNOPSIS
        Discovers all Python cacert.pem files on the system.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param()

    Write-Log "Searching for Python certificate files..."

    $searchRoots = @(
        "$env:ProgramFiles\Python*",
        "${env:ProgramFiles(x86)}\Python*",
        "$env:LOCALAPPDATA\Programs\Python\Python*",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python*",
        "$env:ProgramData\Anaconda*",
        "$env:ProgramData\Miniconda*",
        "$env:USERPROFILE\Anaconda*",
        "$env:USERPROFILE\Miniconda*",
        "$env:USERPROFILE\.conda\envs\*",
        "$env:USERPROFILE\envs\*",
        "$env:ProgramFiles\WindowsApps\*Python*",
        "$env:LOCALAPPDATA\pip\Cache",
        "$env:APPDATA\pip"
    )

    $discoveredFiles = [System.Collections.ArrayList]::new()

    foreach ($root in $searchRoots) {
        $resolvedPaths = Resolve-Path -Path $root -ErrorAction SilentlyContinue

        foreach ($resolvedPath in $resolvedPaths) {
            $files = Get-ChildItem -Path $resolvedPath.Path -Recurse -Filter "cacert.pem" -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                [void]$discoveredFiles.Add($file)
            }
        }
    }

    # Remove duplicates
    $uniqueFiles = $discoveredFiles | Sort-Object -Property FullName -Unique

    Write-Log "Discovered $($uniqueFiles.Count) certificate file(s)"
    return $uniqueFiles
}

#endregion

#region Certificate Update Functions

function Test-NetskopeAlreadyPresent {
    <#
    .SYNOPSIS
        Checks if Netskope certificates have already been appended to the target file.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        return $false
    }

    $content = Get-Content -Path $FilePath -Raw -ErrorAction SilentlyContinue
    return $content -match "# Netskope CA Bundle Appended"
}

function Update-CertificateFile {
    <#
    .SYNOPSIS
        Appends Netskope certificates to a Python certificate file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$NetskopeContent
    )

    try {
        # Check if already updated
        if (Test-NetskopeAlreadyPresent -FilePath $FilePath) {
            Write-Log "Skipping (already updated): $FilePath" -Level WARNING
            $script:Stats.PythonSkipped++
            return
        }

        if ($DryRun) {
            Write-Log "[DRY-RUN] Would update: $FilePath" -Level WARNING
            return
        }

        # Create timestamped backup
        $backupPath = "$FilePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $FilePath -Destination $backupPath -Force

        # Append Netskope certificates with marker
        $marker = @"

# ============================================================================
# Netskope CA Bundle Appended
# Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ============================================================================

"@
        Add-Content -Path $FilePath -Value ($marker + $NetskopeContent) -Encoding UTF8

        Write-Log "Updated: $FilePath" -Level SUCCESS
        $script:Stats.PythonUpdated++
    }
    catch {
        Write-Log "Failed to update $FilePath`: $_" -Level ERROR
        $script:Stats.PythonFailed++
    }
}

#endregion

#region Environment Configuration

function Set-CertificateEnvironmentVariables {
    <#
    .SYNOPSIS
        Configures system-wide certificate environment variables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BundlePath
    )

    Write-Log "Configuring environment variables..."

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would set REQUESTS_CA_BUNDLE=$BundlePath" -Level WARNING
        Write-Log "[DRY-RUN] Would set SSL_CERT_FILE=$BundlePath" -Level WARNING
        return
    }

    try {
        # Set for current session
        $env:REQUESTS_CA_BUNDLE = $BundlePath
        $env:SSL_CERT_FILE = $BundlePath

        # Set system-wide (persistent)
        [Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $BundlePath, "Machine")
        [Environment]::SetEnvironmentVariable("SSL_CERT_FILE", $BundlePath, "Machine")

        Write-Log "REQUESTS_CA_BUNDLE = $BundlePath" -Level SUCCESS
        Write-Log "SSL_CERT_FILE = $BundlePath" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to set environment variables: $_" -Level ERROR
    }
}

#endregion

#region Java Keystore Functions

function Find-JavaInstallations {
    <#
    .SYNOPSIS
        Discovers Java installations on the system.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    Write-Log "Searching for Java installations..."

    $javaHomes = [System.Collections.ArrayList]::new()

    # Check JAVA_HOME environment variable
    $javaHomeEnv = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ($javaHomeEnv -and (Test-Path $javaHomeEnv)) {
        [void]$javaHomes.Add($javaHomeEnv)
    }

    # Common Java installation locations
    $searchRoots = @(
        "$env:ProgramFiles\Java\*",
        "${env:ProgramFiles(x86)}\Java\*",
        "$env:ProgramFiles\Eclipse Adoptium\*",
        "$env:ProgramFiles\Amazon Corretto\*",
        "$env:ProgramFiles\Microsoft\*",
        "$env:ProgramFiles\AdoptOpenJDK\*",
        "$env:ProgramFiles\Zulu\*",
        "$env:LOCALAPPDATA\Programs\Eclipse Adoptium\*"
    )

    foreach ($root in $searchRoots) {
        $resolvedPaths = Resolve-Path -Path $root -ErrorAction SilentlyContinue

        foreach ($path in $resolvedPaths) {
            $keytoolPath = Join-Path -Path $path.Path -ChildPath "bin\keytool.exe"
            if (Test-Path -Path $keytoolPath -PathType Leaf) {
                [void]$javaHomes.Add($path.Path)
            }
        }
    }

    # Remove duplicates
    $uniqueHomes = $javaHomes | Sort-Object -Unique

    Write-Log "Found $($uniqueHomes.Count) Java installation(s)"
    return $uniqueHomes
}

function Find-JavaKeystores {
    <#
    .SYNOPSIS
        Discovers Java cacerts keystore files.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    Write-Log "Searching for Java keystores..."

    $keystores = [System.Collections.ArrayList]::new()
    $javaHomes = Find-JavaInstallations

    foreach ($javaHome in $javaHomes) {
        # Check common locations within Java installation
        $possibleLocations = @(
            (Join-Path -Path $javaHome -ChildPath "lib\security\cacerts"),
            (Join-Path -Path $javaHome -ChildPath "jre\lib\security\cacerts")
        )

        foreach ($cacertsPath in $possibleLocations) {
            if (Test-Path -Path $cacertsPath -PathType Leaf) {
                [void]$keystores.Add($cacertsPath)
            }
        }
    }

    # Remove duplicates
    $uniqueKeystores = $keystores | Sort-Object -Unique

    Write-Log "Discovered $($uniqueKeystores.Count) Java keystore(s)"
    return $uniqueKeystores
}

function Test-NetskopeInKeystore {
    <#
    .SYNOPSIS
        Checks if Netskope certificate already exists in a Java keystore.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$KeystorePath
    )

    # Find keytool
    $javaHome = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $KeystorePath))
    $keytoolPath = Join-Path -Path $javaHome -ChildPath "bin\keytool.exe"

    if (-not (Test-Path $keytoolPath)) {
        # Try to find keytool in PATH
        $keytoolPath = (Get-Command keytool.exe -ErrorAction SilentlyContinue).Source
        if (-not $keytoolPath) {
            Write-Log "keytool.exe not found for $KeystorePath" -Level WARNING
            return $false
        }
    }

    # Check if alias exists
    $listOutput = & $keytoolPath -list -keystore $KeystorePath `
        -storepass $script:JavaKeystorePassword `
        -alias $script:NetskopeAlias 2>&1

    return $LASTEXITCODE -eq 0
}

function Update-JavaKeystore {
    <#
    .SYNOPSIS
        Imports Netskope certificate into a Java keystore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeystorePath,

        [Parameter(Mandatory)]
        [string]$CertificateFile
    )

    try {
        # Check if already present
        if (Test-NetskopeInKeystore -KeystorePath $KeystorePath) {
            Write-Log "Skipping (already present): $KeystorePath" -Level WARNING
            $script:Stats.JavaSkipped++
            return
        }

        if ($DryRun) {
            Write-Log "[DRY-RUN] Would update keystore: $KeystorePath" -Level WARNING
            return
        }

        # Find keytool
        $javaHome = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $KeystorePath))
        $keytoolPath = Join-Path -Path $javaHome -ChildPath "bin\keytool.exe"

        if (-not (Test-Path $keytoolPath)) {
            $keytoolPath = (Get-Command keytool.exe -ErrorAction SilentlyContinue).Source
            if (-not $keytoolPath) {
                throw "keytool.exe not found"
            }
        }

        # Create backup
        $backupPath = "$KeystorePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $KeystorePath -Destination $backupPath -Force

        # Import certificate
        $importArgs = @(
            "-import"
            "-noprompt"
            "-trustcacerts"
            "-alias", $script:NetskopeAlias
            "-file", $CertificateFile
            "-keystore", $KeystorePath
            "-storepass", $script:JavaKeystorePassword
        )

        $result = & $keytoolPath $importArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Updated Java keystore: $KeystorePath" -Level SUCCESS
            $script:Stats.JavaUpdated++
        }
        else {
            throw "keytool import failed: $result"
        }
    }
    catch {
        Write-Log "Failed to update keystore $KeystorePath`: $_" -Level ERROR
        $script:Stats.JavaFailed++

        # Restore backup if it exists
        $backupPath = "$KeystorePath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (Test-Path $backupPath) {
            Copy-Item -Path $backupPath -Destination $KeystorePath -Force
        }
    }
}

#endregion

#region Log Export

function Export-LogFile {
    <#
    .SYNOPSIS
        Exports the session log to a file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $logFileName = "netskope_cert_update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $logPath = Join-Path -Path $env:TEMP -ChildPath $logFileName

    $script:UpdateLog | Out-File -FilePath $logPath -Encoding UTF8
    Write-Log "Log exported: $logPath"

    return $logPath
}

#endregion

#region Main Execution

function Invoke-Main {
    Write-Banner

    if ($DryRun) {
        Write-Log "Running in DRY-RUN mode - no changes will be made" -Level WARNING
        Write-Host ""
    }

    try {
        # Step 1: Initialize Netskope bundle
        $bundlePath = Initialize-NetskopeBundle

        # Step 2: Get bundle content
        $netskopeContent = if (-not $DryRun -and (Test-Path $bundlePath)) {
            Get-Content -Path $bundlePath -Raw
        }
        else {
            ""
        }

        # Create temporary certificate file for Java import
        $tempCertFile = Join-Path -Path $env:TEMP -ChildPath "netskope_cert_$([System.Guid]::NewGuid()).pem"
        if (-not $DryRun -and (Test-Path $bundlePath)) {
            # Extract just the Netskope certificate for Java import
            $netskopeOnly = Get-Content -Path "$NetskopeDataPath\nscacert.pem" -ErrorAction SilentlyContinue
            if ($netskopeOnly) {
                $netskopeOnly | Out-File -FilePath $tempCertFile -Encoding ASCII
            }
        }

        # Step 3: Update Python certificates
        if (-not $SkipPython) {
            $certFiles = Find-PythonCertificateFiles

            if ($certFiles.Count -eq 0) {
                Write-Log "No Python certificate files found" -Level WARNING
            }
            else {
                Write-Host ""
                Write-Log "Updating Python certificate files..."

                foreach ($file in $certFiles) {
                    Update-CertificateFile -FilePath $file.FullName -NetskopeContent $netskopeContent
                }
            }
        }

        # Step 4: Update Java keystores
        if (-not $SkipJava) {
            Write-Host ""
            $keystores = Find-JavaKeystores

            if ($keystores.Count -eq 0) {
                Write-Log "No Java keystores found" -Level WARNING
            }
            else {
                Write-Log "Updating Java keystores..."

                foreach ($keystore in $keystores) {
                    if (Test-Path $tempCertFile) {
                        Update-JavaKeystore -KeystorePath $keystore -CertificateFile $tempCertFile
                    }
                }
            }
        }

        # Cleanup temporary file
        if (Test-Path $tempCertFile) {
            Remove-Item -Path $tempCertFile -Force -ErrorAction SilentlyContinue
        }

        # Step 5: Configure environment variables
        Write-Host ""
        Set-CertificateEnvironmentVariables -BundlePath $bundlePath

        # Step 6: Display summary
        Write-Summary

        # Step 7: Export log
        $logPath = Export-LogFile

        Write-Host "Restart your terminal or applications for changes to take effect." -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Log "Script execution failed: $_" -Level ERROR
        Export-LogFile
        exit 1
    }
}

# Entry point
Invoke-Main

#endregion
