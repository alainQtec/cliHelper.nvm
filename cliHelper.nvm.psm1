
#!/usr/bin/env pwsh
#region    Classes
class NodeVersion {
  [string]$Version
  [string]$Date
  [string[]]$Files
  [string]$Npm
  [string]$V8
  [string]$UV
  [string]$Zlib
  [string]$OpenSSL
  [string]$Modules
  [string]$LTS
  [bool]$Security

  NodeVersion([PSCustomObject]$obj) {
    $this.Version = $obj.version
    $this.Date = $obj.date
    $this.Files = $obj.files
    $this.Npm = $obj.npm
    $this.V8 = $obj.v8
    $this.UV = $obj.uv
    $this.Zlib = $obj.zlib
    $this.OpenSSL = $obj.openssl
    $this.Modules = $obj.modules
    $this.LTS = $obj.lts
    $this.Security = $obj.security
  }
}

class NVM {
  static [string]$BaseDirectory
  static [string]$CurrentVersion
  static [System.Collections.ArrayList]$InstalledVersions
  static [string]$SourceBaseUrl = "https://nodejs.org/dist"

  static NVM() {
    [NVM]::BaseDirectory = Join-Path $env:USERPROFILE '.nvm-ps'
    [NVM]::InstalledVersions = [System.Collections.ArrayList]::new()

    if (-not (Test-Path [NVM]::BaseDirectory)) {
      New-Item -ItemType Directory -Path [NVM]::BaseDirectory | Out-Null
    }

    $versionFile = Join-Path [NVM]::BaseDirectory 'current'
    if (Test-Path $versionFile) {
      [NVM]::CurrentVersion = Get-Content $versionFile
    }

    [NVM]::RefreshInstalledVersions()
  }

  static [void] RefreshInstalledVersions() {
    [NVM]::InstalledVersions.Clear()
    if (Test-Path [NVM]::BaseDirectory) {
      Get-ChildItem -Path [NVM]::BaseDirectory -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        ForEach-Object { [NVM]::InstalledVersions.Add($_.Name) }
    }
  }

  static [array] ListVersions() {
    [NVM]::RefreshInstalledVersions()
    return [NVM]::InstalledVersions
  }

  static [string] GetCurrentVersion() {
    return [NVM]::CurrentVersion
  }

  static [array] ListRemoteVersions() {
    $indexPath = Join-Path [NVM]::BaseDirectory "index.json"

    try {
      $webClient = New-Object System.Net.WebClient
      $webClient.Headers.Add("User-Agent", "NVM PowerShell/1.0")
      $webClient.DownloadFile("$([NVM]::SourceBaseUrl)/index.json", $indexPath)

      $versions = Get-Content $indexPath | ConvertFrom-Json
      return $versions | ForEach-Object { [NodeVersion]::new($_) }
    } catch {
      Write-Error "Failed to fetch remote versions: $_"
      return @()
    }
  }

  static [void] Install([string]$version, [bool]$lts = $false) {
    if ($lts) {
      $versions = [NVM]::ListRemoteVersions()
      $ltsVersion = $versions | Where-Object { $null -ne $_.LTS } | Select-Object -First 1
      if ($null -ne $ltsVersion) {
        $version = $ltsVersion.Version
      } else {
        Write-Error "No LTS version found"
        return
      }
    }

    $nodeDir = Join-Path [NVM]::BaseDirectory $version

    if (Test-Path $nodeDir) {
      Write-Host "Version $version is already installed."
      return
    }

    New-Item -ItemType Directory -Path $nodeDir | Out-Null

    $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $os = if ($IsWindows) { "win" } elseif ($IsMacOS) { "darwin" } else { "linux" }
    $ext = if ($IsWindows) { "zip" } else { "tar.gz" }

    $downloadUrl = "$([NVM]::SourceBaseUrl)/v$version/node-v$version-$os-$architecture.$ext"
    $downloadPath = Join-Path [NVM]::BaseDirectory "node-v$version.$ext"

    try {
      Write-Host "Downloading Node.js $version..."
      $webClient = New-Object System.Net.WebClient
      $webClient.Headers.Add("User-Agent", "NVM PowerShell/1.0")
      $webClient.DownloadFile($downloadUrl, $downloadPath)

      Write-Host "Extracting..."
      if ($IsWindows) {
        Expand-Archive -Path $downloadPath -DestinationPath $nodeDir -Force
        $extractedDir = Get-ChildItem -Path $nodeDir -Directory | Select-Object -First 1
        Move-Item -Path "$($extractedDir.FullName)\*" -Destination $nodeDir
        Remove-Item $extractedDir.FullName
      } else {
        tar -xzf $downloadPath -C $nodeDir
        $extractedDir = Get-ChildItem -Path $nodeDir -Directory | Select-Object -First 1
        Move-Item -Path "$($extractedDir.FullName)\*" -Destination $nodeDir
        Remove-Item $extractedDir.FullName
      }

      Remove-Item $downloadPath
      Write-Host "Node.js $version has been installed successfully."
      [NVM]::RefreshInstalledVersions()
    } catch {
      Write-Host "Failed to install Node.js $version. Error: $_"
      if (Test-Path $nodeDir) {
        Remove-Item -Path $nodeDir -Recurse -Force
      }
    }
  }

  static [void] Use([string]$version) {
    $nodeDir = Join-Path [NVM]::BaseDirectory $version

    if (-not (Test-Path $nodeDir)) {
      Write-Host "Version $version is not installed. Please install it first."
      return
    }

    $nodeBinPath = if (-not $IsWindows) {
      Join-Path $nodeDir "bin"
    } else {
      $nodeDir
    }

    $env:Path = "$nodeBinPath;" + ($env:Path -split ';' | Where-Object { $_ -notmatch 'nodejs|node-v\d+\.\d+\.\d+' } | Join-String -Separator ';')

    [NVM]::CurrentVersion = $version
    $versionFile = Join-Path [NVM]::BaseDirectory 'current'
    Set-Content -Path $versionFile -Value $version

    Write-Host "Now using Node.js $version"
  }

  static [void] Uninstall([string]$version) {
    $nodeDir = Join-Path [NVM]::BaseDirectory $version

    if (-not (Test-Path $nodeDir)) {
      Write-Host "Version $version is not installed."
      return
    }

    if ([NVM]::CurrentVersion -eq $version) {
      Write-Host "Cannot uninstall current version. Please switch to another version first."
      return
    }

    try {
      Remove-Item -Path $nodeDir -Recurse -Force
      Write-Host "Node.js $version has been uninstalled."
      [NVM]::RefreshInstalledVersions()
    } catch {
      Write-Host "Failed to uninstall Node.js $version. Error: $_"
    }
  }
}

# Create instance and parse arguments
# switch ($args[0]) {
#   "list" {
#     Write-Host "Installed versions:"
#     [NVM]::ListVersions() | ForEach-Object {
#       if ($_ -eq [NVM]::GetCurrentVersion()) {
#         Write-Host "* $_ (current)"
#       } else {
#         Write-Host "  $_"
#       }
#     }
#   }
#   "ls-remote" {
#     Write-Host "Available versions:"
#     [NVM]::ListRemoteVersions() | ForEach-Object {
#       $ltsMarker = if ($null -ne $_.LTS) { " (LTS)" } else { "" }
#       Write-Host "  $($_.Version)$ltsMarker"
#     }
#   }
#   "install" {
#     if ($args[1] -eq "--lts") {
#       [NVM]::Install("", $true)
#     } elseif ($args[1]) {
#       [NVM]::Install($args[1], $false)
#     } else {
#       Write-Host "Please specify a version to install or use --lts"
#     }
#   }
#   "use" {
#     if ($args[1]) {
#       [NVM]::Use($args[1])
#     } else {
#       Write-Host "Please specify a version to use"
#     }
#   }
#   "uninstall" {
#     if ($args[1]) {
#       [NVM]::Uninstall($args[1])
#     } else {
#       Write-Host "Please specify a version to uninstall"
#     }
#   }
#   default {
#     Write-Host @"
# Node Version Manager PowerShell Script

# Usage:
#     .\nvm list              - List installed versions
#     .\nvm ls-remote         - List available versions
#     .\nvm install <version> - Install specified Node.js version
#     .\nvm install --lts     - Install latest LTS version
#     .\nvm use <version>     - Use specified Node.js version
#     .\nvm uninstall <version> - Uninstall specified Node.js version
# "@
#   }
# }
#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [NodeVersion]
  [NVM]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
