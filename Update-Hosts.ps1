<#
.SYNOPSIS
Downloads hosts file entries from a specific URL and updates the local Windows hosts file.
.DESCRIPTION
This script fetches hosts file content defined between specific markers from a GitHub URL.
It checks the local hosts file (C:\Windows\System32\drivers\etc\hosts) for an existing
block marked with '# <-- COOL-LAB HOSTS BEGIN -->' and '# <-- COOL-LAB HOSTS END -->'.
If the block exists, it's replaced with the downloaded content.
If not, the downloaded content (including markers) is appended to the end of the file.
Requires administrative privileges to run.
.NOTES
File Name : Update-CoolLabHosts.ps1
Author    : Gemini
Requires  : PowerShell 5.1 or higher, Administrator privileges.
.LINK
URL for hosts content: https://raw.githubusercontent.com/COOLLab-CQU/DevOps-Docs/refs/heads/master/hosts
#>

#Requires -RunAsAdministrator

# --- Configuration ---
$sourceUrl = "https://cdn.jsdelivr.net/gh/COOLLab-CQU/DevOps-Docs/hosts"
$hostsFilePath = "C:\Windows\System32\drivers\etc\hosts" # Standard Windows hosts file path
$startMarker = "# <-- COOL-LAB HOSTS BEGIN -->"
$endMarker = "# <-- COOL-LAB HOSTS END -->"
# Use a temporary file path
$tempFilePath = [System.IO.Path]::Combine($env:TEMP, "downloaded_hosts_temp.txt")

# --- Script Body ---
Write-Host "Starting hosts file update process..."

# 1. Download the new hosts content
Write-Host "Attempting to download hosts content from $sourceUrl..."
try {
    # Use Invoke-WebRequest to download the content
    Invoke-WebRequest -Uri $sourceUrl -OutFile $tempFilePath -UseBasicParsing -ErrorAction Stop
    $downloadedContent = Get-Content -Path $tempFilePath -Raw -Encoding UTF8 # Read as a single string, assuming UTF8 from source
    Remove-Item -Path $tempFilePath -Force # Clean up the temporary file
    Write-Host "Successfully downloaded content."

    # Basic validation: Check if downloaded content seems valid (contains markers)
    if (-not ($downloadedContent -match [regex]::Escape($startMarker) -and $downloadedContent -match [regex]::Escape($endMarker))) {
        Write-Error "Downloaded content does not contain the expected start and end markers. Aborting."
        exit 1
    }

} catch {
    Write-Error "Failed to download hosts content from $sourceUrl. Error: $($_.Exception.Message)"
    exit 1
}

# 2. Read the current hosts file
Write-Host "Reading current hosts file: $hostsFilePath"
if (-not (Test-Path $hostsFilePath)) {
    Write-Error "Hosts file not found at $hostsFilePath. Aborting."
    exit 1
}

try {
    # Read the entire hosts file as a single string, preserving line endings
    $currentHostsContent = Get-Content -Path $hostsFilePath -Raw -Encoding Default # Use system default encoding
} catch {
    Write-Error "Failed to read hosts file at $hostsFilePath. Ensure you have permissions. Error: $($_.Exception.Message)"
    exit 1
}

# 3. Check if the marker block exists and update/append
# Prepare regex pattern to find the block (case-sensitive, multi-line)
# (?s) makes '.' match newline characters
$regexPattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"

if ($currentHostsContent -match $regexPattern) {
    Write-Host "Found existing COOL-Lab hosts block. Replacing it..."
    # Replace the existing block with the newly downloaded content
    $newHostsContent = $currentHostsContent -replace $regexPattern, $downloadedContent
} else {
    Write-Host "COOL-Lab hosts block not found. Appending new block..."
    # Append the downloaded content to the end
    # Ensure there's a newline separating the existing content and the new block
    if (-not ($currentHostsContent.EndsWith([Environment]::NewLine)) -and $currentHostsContent.Length -gt 0) {
        $newHostsContent = $currentHostsContent + [Environment]::NewLine + $downloadedContent
    } else {
        $newHostsContent = $currentHostsContent + $downloadedContent
    }
    # Ensure the appended content ends with a newline for good measure
    if (-not $newHostsContent.EndsWith([Environment]::NewLine)) {
         $newHostsContent += [Environment]::NewLine
    }
}

# 4. Write the updated content back to the hosts file
Write-Host "Writing updated content back to $hostsFilePath..."
try {
    # Write the content back using the system's default encoding. Use -Force to overwrite if read-only (admin should handle this)
    Set-Content -Path $hostsFilePath -Value $newHostsContent -Encoding Default -Force -ErrorAction Stop
    Write-Host "Successfully updated the hosts file."
} catch {
    Write-Error "Failed to write updated content to hosts file. Error: $($_.Exception.Message)"
    exit 1
}

Write-Host "Hosts file update process finished."