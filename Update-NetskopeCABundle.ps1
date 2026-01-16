#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Updates Python CA certificate bundles with Netskope certificates on Windows.

.DESCRIPTION
    This script:
    1. Locates or creates the Netskope certificate bundle
    2. Finds all Python cacert.pem files on the system
    3. Appends the Netskope certificates to each bundle
    4. Sets the REQUESTS_CA_BUNDLE environment variable

.PARAMETER NetskopeDataPath
    Path to the Netskope data directory. Defaults to %ProgramData%\Netskope\STAgent\data

.PARAMETER NetskopeBundle
    Name of the Netskope certificate bundle file. Defaults to nscacert_combined.pem

.PARAMETER DryRun
    Preview changes without modifying any files.

.PARAMETER Force
    Recreate the Netskope bundle even if it already exists.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1
    Runs the script with default settings.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1 -DryRun
    Preview what changes would be made without modifying files.

.EXAMPLE
    .\Update-NetskopeCABundle.ps1 -Force
    Force recreation of the Netskope certificate bundle.

.NOTES
    Author: Tim Schwarz
    Version: 1.0.0
    Requires: PowerShell 5.1+, Administrator privileges
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
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script-level variables
$script:UpdateLog = [System.Collections.ArrayList]::new()
$script:Stats = @{
    Updated = 0
    Skipped = 0
    Failed  = 0
}

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
    Files Updated:  $($script:Stats.Updated)
    Files Skipped:  $($script:Stats.Skipped)
    Files Failed:   $($script:Stats.Failed)
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
            $script:Stats.Skipped++
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
        $script:Stats.Updated++
    }
    catch {
        Write-Log "Failed to update $FilePath`: $_" -Level ERROR
        $script:Stats.Failed++
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

        # Step 3: Find Python certificate files
        $certFiles = Find-PythonCertificateFiles

        if ($certFiles.Count -eq 0) {
            Write-Log "No Python certificate files found" -Level WARNING
        }
        else {
            Write-Host ""
            Write-Log "Updating certificate files..."

            foreach ($file in $certFiles) {
                Update-CertificateFile -FilePath $file.FullName -NetskopeContent $netskopeContent
            }
        }

        # Step 4: Configure environment variables
        Write-Host ""
        Set-CertificateEnvironmentVariables -BundlePath $bundlePath

        # Step 5: Display summary
        Write-Summary

        # Step 6: Export log
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
