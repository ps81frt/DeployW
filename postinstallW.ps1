# ============================================================
# POST-INSTALL - ps81frt
# Run as Administrator
# ============================================================

$shell = New-Object -ComObject WScript.Shell
$startMenu = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
$log = "$PSScriptRoot\install-errors.log"
"[$(Get-Date)] START" | Out-File $log -Append
trap { "[$(Get-Date)] ERROR: $_" | Out-File $log -Append }

# ============================================================
# CONFIGURATION
# ============================================================

$RUN_MODULES     = $true
$RUN_LINUXTOOLS  = $true
$RUN_WINTOOLKIT  = $true
$RUN_PASTEBINIT  = $true
$RUN_HCICONF     = $true
$RUN_WINGET      = $true
$RUN_GH_RELEASES = $true
$RUN_DOTFILES    = $true
$RUN_HARDENING   = $true
$RUN_LOCKSCREEN  = $true
$RUN_BACKGROUND  = $true

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERREUR] Relancer en tant qu'Administrateur" -ForegroundColor Red
    exit 1
}

function Get-GHRelease {
    param($repo)
    $delays = @(0, 3, 10)   # j'essaie 1 immediate, puis +3s, puis +10s
    foreach ($delay in $delays) {
        if ($delay -gt 0) {
            "[$(Get-Date)] WARN Get-GHRelease $repo : retry dans $delay s" | Out-File $log -Append
            Start-Sleep -Seconds $delay
        }
        try {
            $result = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "ps81frt-installer" }
            return $result
        } catch {
            $status  = $_.Exception.Response.StatusCode.value__
            $message = $_.Exception.Message
            # 404 = repo absent ou NO release
            if ($status -eq 404) {
                "[$(Get-Date)] ERROR Get-GHRelease $repo : 404 repo/release introuvable" | Out-File $log -Append
                return $null
            }
            "[$(Get-Date)] WARN Get-GHRelease $repo : $message | Status: $status" | Out-File $log -Append
        }
    }
    "[$(Get-Date)] ERROR Get-GHRelease $repo : echec apres $($delays.Count) tentatives" | Out-File $log -Append
    return $null
}

function Get-GHAsset {
    param($release, $pattern)
    if (-not $release) { return $null }
    $release.assets | Where-Object { $_.name -match "(?i)$pattern" } | Select-Object -First 1
}

function Install-GHApp {
    param(
        [string]$Repo,
        [string]$Dest,
        [string]$Pattern = "\.(exe|zip)$",
        [string]$ShortcutName,
        [switch]$AllowPs1
    )

    $r = Get-GHRelease $Repo
    if (-not $r) { return }

    $newTag      = $r.tag_name
    $versionFile = "$Dest\.version"
    $currentTag  = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "" }

    if ($currentTag -eq $newTag) {
        Write-Host "[SKIP] $Repo $newTag deja installe" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP $Repo $newTag already installed" | Out-File $log -Append
        return
    }

    $asset = Get-GHAsset $r $Pattern
    if (-not $asset) {
        Write-Host "[SKIP] $Repo : aucun asset correspondant a '$Pattern'" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP $Repo no matching asset" | Out-File $log -Append
        return
    }

    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $dl     = "$env:TEMP\$($asset.name)"
    $action = if ($currentTag) { "Mise a jour $currentTag -> $newTag" } else { "Installation $newTag" }
    Write-Host "[...] $Repo : $action..." -ForegroundColor Yellow
    "[$(Get-Date)] START $Repo $action" | Out-File $log -Append
    DlFile $asset.browser_download_url $dl

    $exe = $null
    if ($asset.name -match "(?i)\.zip$") {
        Expand-Archive $dl -DestinationPath $Dest -Force
        $exe = Get-ChildItem $Dest -Filter "*.exe" -Recurse |
               Sort-Object -Property Length -Descending | Select-Object -First 1
        if (-not $exe -and $AllowPs1) {
            $ps1 = Get-ChildItem $Dest -Filter "*.ps1" -Recurse | Select-Object -First 1
            if ($ps1) {
                Write-Host "[OK] $Repo $newTag installe (ps1 : $($ps1.Name))" -ForegroundColor Green
                "[$(Get-Date)] INSTALLED $Repo $newTag ps1 $($ps1.FullName)" | Out-File $log -Append
                $newTag | Set-Content $versionFile -Encoding UTF8
                Remove-Item $dl -ErrorAction SilentlyContinue
                return
            }
            $contents = (Get-ChildItem $Dest -Recurse | Select-Object -ExpandProperty Name) -join ", "
            Write-Host "[ERREUR] $Repo : aucun exe/ps1. Contenu : $contents" -ForegroundColor Red
            "[$(Get-Date)] ERROR $Repo exe not found. Contents: $contents" | Out-File $log -Append
            Remove-Item $dl -ErrorAction SilentlyContinue
            return
        }
    } else {
        Copy-Item $dl "$Dest\$($asset.name)" -Force
        if ($asset.name -match "(?i)\.exe$") {
            $exe = Get-Item "$Dest\$($asset.name)"
        } elseif ($AllowPs1 -and $asset.name -match "(?i)\.ps1$") {
            Write-Host "[OK] $Repo $newTag installe (ps1 : $($asset.name))" -ForegroundColor Green
            "[$(Get-Date)] INSTALLED $Repo $newTag ps1 $Dest\$($asset.name)" | Out-File $log -Append
            $newTag | Set-Content $versionFile -Encoding UTF8
            Remove-Item $dl -ErrorAction SilentlyContinue
            return
        }
    }
    Remove-Item $dl -ErrorAction SilentlyContinue

    if ($exe) {
        if ($ShortcutName) { New-Shortcut $ShortcutName $exe.FullName $exe.DirectoryName }
        Write-Host "[OK] $Repo $newTag installe ($($exe.Name))" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED $Repo $newTag $($exe.Name)" | Out-File $log -Append
        $newTag | Set-Content $versionFile -Encoding UTF8
    } else {
        $contents = (Get-ChildItem $Dest -Recurse | Select-Object -ExpandProperty Name) -join ", "
        Write-Host "[ERREUR] $Repo : exe non trouve. Contenu : $contents" -ForegroundColor Red
        "[$(Get-Date)] ERROR $Repo exe not found. Contents: $contents" | Out-File $log -Append
    }
}

function New-Shortcut {
    param($name, $target, $workdir)
    $lnk = $shell.CreateShortcut("$startMenu\$name.lnk")
    $lnk.TargetPath = $target
    $lnk.WorkingDirectory = $workdir
    $lnk.Save()
}

function DlFile {
    param($url, $dest)
    if (-not $url) {
        "[$(Get-Date)] ERROR DlFile URL vide -> $dest" | Out-File $log -Append
        Write-Host "  [ERREUR] URL vide pour $dest" -ForegroundColor Red
        return
    }
    "[$(Get-Date)] START DlFile $dest" | Out-File $log -Append
    try {
        Invoke-WebRequest $url -OutFile $dest
        if (Test-Path $dest) {
            "[$(Get-Date)] OK DlFile $dest" | Out-File $log -Append
        } else {
            "[$(Get-Date)] ERROR DlFile fichier absent apres download $dest" | Out-File $log -Append
            Write-Host "  [ERREUR] Fichier absent apres download : $dest" -ForegroundColor Red
        }
    } catch {
        "[$(Get-Date)] ERROR DlFile $dest : $_" | Out-File $log -Append
        Write-Host "  [ERREUR] Download echoue : $dest" -ForegroundColor Red
    }
}

# ============================================================
# MODULES
# ============================================================

if ($RUN_MODULES) {

$mod = "PSScriptAnalyzer"
$installed = Get-Module -ListAvailable $mod | Sort-Object Version -Descending | Select-Object -First 1
$latest = Find-Module $mod -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $installed -or ($latest -and $installed.Version -lt $latest.Version)) {
    Write-Host "[...] Installation module $mod..." -ForegroundColor Yellow
    Install-Module $mod -Force -Scope CurrentUser
    Write-Host "[OK] Module $mod $($latest.Version) installe" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED module $mod $($latest.Version)" | Out-File $log -Append
} else {
    Write-Host "[SKIP] Module $mod $($installed.Version) deja a jour" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP module $mod $($installed.Version) already latest" | Out-File $log -Append
}

$mod = "ps2exe"
$installed = Get-Module -ListAvailable $mod | Sort-Object Version -Descending | Select-Object -First 1
$latest = Find-Module $mod -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $installed -or ($latest -and $installed.Version -lt $latest.Version)) {
    Write-Host "[...] Installation module $mod..." -ForegroundColor Yellow
    Install-Module $mod -Force -Scope CurrentUser
    Write-Host "[OK] Module $mod $($latest.Version) installe" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED module $mod $($latest.Version)" | Out-File $log -Append
} else {
    Write-Host "[SKIP] Module $mod $($installed.Version) deja a jour" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP module $mod $($installed.Version) already latest" | Out-File $log -Append
}

}

# ============================================================
# LINUX TOOLS
# ============================================================

if ($RUN_LINUXTOOLS) {

$linuxDir     = "C:\Program Files\LinuxToolOn-Windows"
$linuxVersion = "$linuxDir\.version"
# Sentinel fiable : fichier .version dans le dossier d installation
# (System32\ls.exe n existe pas - ls est un alias PowerShell natif)
if (Test-Path $linuxVersion) {
    Write-Host "[SKIP] LinuxToolOn-Windows deja installe ($(Get-Content $linuxVersion -Raw))" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP LinuxToolOn-Windows already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Telechargement LinuxToolOn-Windows..." -ForegroundColor Yellow
    "[$(Get-Date)] START LinuxToolOn-Windows" | Out-File $log -Append
    New-Item -ItemType Directory -Path $linuxDir -Force | Out-Null
    Invoke-WebRequest -Uri "https://github.com/ps81frt/LinuxToolsOnWindows/releases/latest/download/LinuxToolOn-Windows.zip" -OutFile "$env:TEMP\LinuxToolOn-Windows.zip"
    Expand-Archive "$env:TEMP\LinuxToolOn-Windows.zip" -DestinationPath $linuxDir -Force
    # Le zip peut extraire dans un sous-dossier -> chercher recursivement
    $exes = Get-ChildItem $linuxDir -Filter "*.exe" -Recurse
    if ($exes.Count -eq 0) {
        Write-Host "  [ERREUR] LinuxTools : aucun exe trouve dans l archive" -ForegroundColor Red
        "[$(Get-Date)] ERROR LinuxToolOn-Windows no exe found in archive" | Out-File $log -Append
    } else {
        $copiedCount = ($exes | Copy-Item -Destination "C:\Windows\System32\" -Force -PassThru).Count
        # Stocker la date d install comme version sentinel
        (Get-Date -Format 'yyyy-MM-dd') | Set-Content $linuxVersion -Encoding UTF8
        Write-Host "[OK] LinuxTools $copiedCount exe copies dans System32" -ForegroundColor Green
        "[$(Get-Date)] OK LinuxToolOn-Windows $copiedCount exe copies dans System32" | Out-File $log -Append
    }
    Remove-Item $linuxDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\LinuxToolOn-Windows.zip" -Force -ErrorAction SilentlyContinue
}

}

# ============================================================
# CONFIGURATION DU PATH
# ============================================================

$pathType = [EnvironmentVariableTarget]::Machine

$currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
if ($currentPath -notlike "*C:\Windows\System32*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;C:\Windows\System32", $pathType)
    Write-Host "[OK] Path System32 mis a jour" -ForegroundColor Green
}

Remove-Item "$env:TEMP\LinuxToolOn-Windows.zip" -Force -ErrorAction SilentlyContinue

# ============================================================
# WINTOOLKIT
# ============================================================

if ($RUN_WINTOOLKIT) {

$wtkPath   = "C:\Program Files\Wintoolkit"
$wtkScript = "$wtkPath\Wintoolkit.ps1"
if (Test-Path $wtkScript) {
    Write-Host "[SKIP] Wintoolkit deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP Wintoolkit already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Installation Wintoolkit..." -ForegroundColor Yellow
    New-Item -Path $wtkPath -ItemType Directory -Force | Out-Null
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    Add-MpPreference -ExclusionPath $wtkPath
    Invoke-WebRequest https://raw.githubusercontent.com/ps81frt/WintoolKit/main/Wintoolkit.ps1 -OutFile $wtkScript
    Unblock-File -Path $wtkScript
    if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
    if ((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue) -notlike '*Wintoolkit.ps1*') {
        Add-Content -Path $PROFILE -Value 'function Wintoolkit { & "C:\Program Files\Wintoolkit\Wintoolkit.ps1" }'
    }
    $currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
    if ($currentPath -notlike "*$wtkPath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$wtkPath", $pathType)
        "[$(Get-Date)] PATH updated $wtkPath" | Out-File $log -Append
    }
    Write-Host "[OK] Wintoolkit installe et profil mis a jour" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED Wintoolkit" | Out-File $log -Append
}

}

# ============================================================
# PASTEBINIT
# ============================================================

if ($RUN_PASTEBINIT) {

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$modulePath   = "$HOME\Documents\WindowsPowerShell\Modules\pastebinit"
$pasteScript  = "$modulePath\pastebinit.psm1"
if (Test-Path $pasteScript) {
    Write-Host "[SKIP] pastebinit deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP pastebinit already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Installation pastebinit..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $modulePath | Out-Null
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ps81frt/paste-binit/main/pastebinit.psm1" -OutFile $pasteScript
    Import-Module pastebinit
    Write-Host "[OK] pastebinit installe (PS5)" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED pastebinit" | Out-File $log -Append
}

}

# ============================================================
# HCICONF-W
# ============================================================

if ($RUN_HCICONF) {

& {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    Invoke-WebRequest https://github.com/ps81frt/hciconf-W/releases/download/1.0/hciconfig.zip -OutFile "$env:TEMP\hciconf-W.zip"
    Unblock-File "$env:TEMP\hciconf-W.zip"
    Expand-Archive "$env:TEMP\hciconf-W.zip" -DestinationPath "$env:TEMP\hciconf-W" -Force
    Remove-Item "$env:TEMP\hciconf-W.zip"
    $srcDir = "$env:TEMP\hciconf-W"
    $srcPsd = "$srcDir\hciconfig.psd1"
    $dest5 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\hciconfig"
    $dest7 = "$env:USERPROFILE\Documents\PowerShell\Modules\hciconfig"
    New-Item -ItemType Directory -Force -Path $dest5 | Out-Null
    New-Item -ItemType Directory -Force -Path $dest7 | Out-Null

    $src5 = "$srcDir\hciconfig5.psm1"
    if (Test-Path $src5) {
        $target5 = "$dest5\hciconfig.psm1"
        if (Test-Path $target5) { Remove-Item $target5 -Force }
        Copy-Item $src5 $target5 -Force
        Unblock-File $target5
        $bytes = [System.IO.File]::ReadAllBytes($target5)
        if ($bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
            $bom = [byte[]](0xEF, 0xBB, 0xBF)
            $bytes = $bom + $bytes
            [System.IO.File]::WriteAllBytes($target5, $bytes)
        }
        if (Test-Path $srcPsd) { Copy-Item $srcPsd "$dest5\hciconfig.psd1" -Force }
        Write-Host "  [OK] Installe pour PS5.1 : $dest5" -ForegroundColor Green
    }

    $src7 = "$srcDir\hciconfig.psm1"
    if (Test-Path $src7) {
        $target7 = "$dest7\hciconfig.psm1"
        if (Test-Path $target7) { Remove-Item $target7 -Force }
        Copy-Item $src7 $target7 -Force
        Unblock-File $target7
        if (Test-Path $srcPsd) {
            $psd7 = "$dest7\hciconfig.psd1"
            Copy-Item $srcPsd $psd7 -Force
            (Get-Content $psd7 -Raw) -replace "PowerShellVersion\s*=\s*'5\.1'", "PowerShellVersion = '7.0'" | Set-Content $psd7 -Encoding UTF8
        }
        Write-Host "  [OK] Installe pour PS7 : $dest7" -ForegroundColor Green
    }

    $pathTypeUser = [EnvironmentVariableTarget]::User
    $modPath5 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    $modPath7 = "$env:USERPROFILE\Documents\PowerShell\Modules"
    $currentModPath = [Environment]::GetEnvironmentVariable('PSModulePath', $pathTypeUser)

    if ($currentModPath -notlike "*$modPath5*") {
        $currentModPath = "$currentModPath;$modPath5"
        [Environment]::SetEnvironmentVariable('PSModulePath', $currentModPath, $pathTypeUser)
    }
    if ($currentModPath -notlike "*$modPath7*") {
        $currentModPath = [Environment]::GetEnvironmentVariable('PSModulePath', $pathTypeUser)
        $currentModPath = "$currentModPath;$modPath7"
        [Environment]::SetEnvironmentVariable('PSModulePath', $currentModPath, $pathTypeUser)
    }
    Remove-Item "$env:TEMP\hciconf-W" -Recurse -Force
}

}

# ============================================================
# WINGET APPS
# ============================================================

if ($RUN_WINGET) {

$apps = @(
    "7zip.7zip",
    "M2Team.NanaZip",
    "Microsoft.VisualStudioCode",
    #"Google.Chrome.EXE",
    "LibreWolf.LibreWolf",
    "Vivaldi.Vivaldi",
    "Mozilla.Thunderbird.fr",
    "OBSProject.OBSStudio",
    "NickeManarin.ScreenToGif",
    "Flameshot.Flameshot",
    "GitHub.GitHubDesktop",
    "Gyan.FFmpeg.Essentials",
    "smartmontools.smartmontools",
    "Microsoft.PowerShell",
    "Microsoft.WindowsTerminal",
    "IrfanSkiljan.IrfanView",
    "KDE.Okular",
    #"Rustlang.Rustup",
    #"Python.Python.3.14",
    "ImageMagick.ImageMagick",
    "WestWind.MarkdownMonster",
    "Microsoft.DotNet.SDK.10",
    "Microsoft.WinDbg",
    "dorssel.usbipd-win",
    "SergeyFilippov.RegistryFinder",
    #"Insecure.Nmap",
    #"ElaborateBytes.VirtualCloneDrive",
    #"Valve.Steam",
    #"Spotify.Spotify",
    "vim.vim"
)

$appPaths = @{
    "Gyan.FFmpeg.Essentials"        = "C:\Program Files\FFmpeg\bin"
    "smartmontools.smartmontools"   = "C:\Program Files\smartmontools\bin"
    "dorssel.usbipd-win"            = "C:\Program Files\usbipd-win"
    "SergeyFilippov.RegistryFinder" = "C:\Program Files\Registry Finder"
    "Insecure.Nmap"                 = "C:\Program Files (x86)\Nmap"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning "winget non disponible — bloc apps ignoré"
    "[$(Get-Date)] WARNING winget non disponible" | Out-File $log -Append
} else {
    $noAdminApps = @("Spotify.Spotify")

    foreach ($app in $apps) {
        winget list --id $app -e | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SKIP] $app deja installe" -ForegroundColor Cyan
            "[$(Get-Date)] SKIP winget $app already installed" | Out-File $log -Append
        } else {
            Write-Host "[...] Installation $app..." -ForegroundColor Yellow
            "[$(Get-Date)] START winget $app" | Out-File $log -Append

            if ($noAdminApps -contains $app) {
                $wingetPath = (Get-Command winget -ErrorAction SilentlyContinue).Source
                if (-not $wingetPath) { $wingetPath = 'winget' }
                $argList = "install --id $app -e --silent --accept-package-agreements --accept-source-agreements"
                $taskName = "WingetInstall_$($app -replace '\.','_')"
                $action   = New-ScheduledTaskAction -Execute $wingetPath -Argument $argList
                $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
                $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
                $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
                Start-Sleep -Seconds 60
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                winget list --id $app -e | Out-Null
                $exitCode = $LASTEXITCODE
            } else {
                winget install --id $app -e --silent --accept-package-agreements --accept-source-agreements
                $exitCode = $LASTEXITCODE
            }

            if ($exitCode -eq 0) {
                Write-Host "[OK] $app installe" -ForegroundColor Green
                "[$(Get-Date)] INSTALLED winget $app" | Out-File $log -Append

                $p = $null
                if ($appPaths.ContainsKey($app)) {
                    $p = $appPaths[$app]
                } elseif ($app -eq "vim.vim") {
                    # vim dans C:\Program Files\Vim\vim92\
                    $vimDir = Get-ChildItem "C:\Program Files\Vim" -Filter "vim*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                    if ($vimDir) { $p = $vimDir.FullName } else { $p = "C:\Program Files\Vim" }
                } elseif ($app -eq "ImageMagick.ImageMagick") {
                    $imDir = Get-ChildItem "C:\Program Files" -Filter "ImageMagick*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                    if ($imDir) { $p = $imDir.FullName }
                } elseif ($app -eq "Rustlang.Rustup") {
                    $cargoBin = "$env:USERPROFILE\.cargo\bin"
                    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
                    if ($currentUserPath -notlike "*$cargoBin*") {
                        [Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$cargoBin", [EnvironmentVariableTarget]::User)
                        Write-Host "  [OK] PATH Rustlang.Rustup -> $cargoBin (HKCU)" -ForegroundColor Green
                        "[$(Get-Date)] PATH updated HKCU $cargoBin" | Out-File $log -Append
                    } else {
                        Write-Host "  [SKIP] PATH Rust cargo deja present" -ForegroundColor Cyan
                    }
                }

                if ($p -and (Test-Path $p)) {
                    $currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
                    if ($currentPath -notlike "*$p*") {
                        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$p", $pathType)
                        Write-Host "  [OK] PATH $app -> $p" -ForegroundColor Green
                        "[$(Get-Date)] PATH updated $p" | Out-File $log -Append
                    } else {
                        Write-Host "  [SKIP] PATH $app deja present" -ForegroundColor Cyan
                    }
                } elseif ($p) {
                    Write-Host "  [WARN] PATH $app : chemin introuvable -> $p" -ForegroundColor Yellow
                    "[$(Get-Date)] WARN PATH $app chemin absent $p" | Out-File $log -Append
                }
            } else {
                Write-Host "[ERREUR] $app exit $exitCode" -ForegroundColor Red
                "[$(Get-Date)] ERROR winget $app exit $exitCode" | Out-File $log -Append
            }
        }
    }

    $vimSubDir = Get-ChildItem "C:\Program Files\Vim" -Filter "vim*" -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
    if ($vimSubDir) {
        $vimBin = $vimSubDir.FullName
        $currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
        if ($currentPath -notlike "*$vimBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$vimBin", $pathType)
            Write-Host "  [OK] PATH vim -> $vimBin" -ForegroundColor Green
            "[$(Get-Date)] PATH updated $vimBin" | Out-File $log -Append
        }
    }

    $imSubDir = Get-ChildItem "C:\Program Files" -Filter "ImageMagick*" -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
    if ($imSubDir) {
        $imBin = $imSubDir.FullName
        $currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
        if ($currentPath -notlike "*$imBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$imBin", $pathType)
            Write-Host "  [OK] PATH ImageMagick -> $imBin" -ForegroundColor Green
            "[$(Get-Date)] PATH updated $imBin" | Out-File $log -Append
        }
    }

    $env:Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine) + ";" +
                [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    Write-Host "[OK] PATH session rafraichi apres winget" -ForegroundColor Green
    "[$(Get-Date)] OK PATH refreshed after winget block" | Out-File $log -Append
}

}

$desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
Get-ChildItem "$desktop\*.lnk" | Remove-Item -Force -ErrorAction SilentlyContinue
$desktopUser = [Environment]::GetFolderPath("Desktop")
Get-ChildItem "$desktopUser\*.lnk" | Remove-Item -Force -ErrorAction SilentlyContinue
"[$(Get-Date)] OK Desktop shortcuts cleaned" | Out-File $log -Append

# ============================================================
# GITHUB RELEASES
# ============================================================

if ($RUN_GH_RELEASES) {

$r    = Get-GHRelease "ps81frt/SystemScanPro"
$dest = "C:\Program Files\SystemScanPRO"
New-Item -ItemType Directory -Force -Path "$dest\tools" | Out-Null
$_vf  = "$dest\.version"
$_tag = if ($r) { $r.tag_name } else { $null }
$_cur = if (Test-Path $_vf) { (Get-Content $_vf -Raw).Trim() } else { "" }
if ($_tag -and $_tag -eq $_cur) {
    Write-Host "[SKIP] ps81frt/SystemScanPro $_tag deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP ps81frt/SystemScanPro $_tag already installed" | Out-File $log -Append
} else {
    $exe    = Get-GHAsset $r "SystemScanPRO.*\.exe$"
    $sscore = Get-GHAsset $r "SSCore\.exe$"
    $sscheck= Get-GHAsset $r "SSProCheck\.exe$"
    $action = if ($_cur) { "Mise a jour $_cur -> $_tag" } else { "Installation $_tag" }
    if ($exe) {
        Write-Host "[...] SystemScanPRO : $action..." -ForegroundColor Yellow
        "[$(Get-Date)] START SystemScanPRO $action" | Out-File $log -Append
        DlFile $exe.browser_download_url "$dest\SystemScanPRO.exe"
        Write-Host "[OK] SystemScanPRO.exe installe" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED SystemScanPRO.exe $_tag" | Out-File $log -Append
    }
    if ($sscore) {
        DlFile $sscore.browser_download_url "$dest\tools\SSCore.exe"
        "[$(Get-Date)] INSTALLED SSCore.exe" | Out-File $log -Append
    }
    if ($sscheck) {
        DlFile $sscheck.browser_download_url "$dest\tools\SSProCheck.exe"
        "[$(Get-Date)] INSTALLED SSProCheck.exe" | Out-File $log -Append
    }
    if ($_tag) { $_tag | Set-Content $_vf -Encoding UTF8 }
    New-Shortcut "SystemScanPRO" "$dest\SystemScanPRO.exe" $dest
}

Install-GHApp -Repo "ps81frt/RAMSentinel" -Dest "C:\Program Files\RAMSentinel" `
    -ShortcutName "RAMSentinel"

Install-GHApp -Repo "ps81frt/DRTPro4" -Dest "C:\Program Files\DRTPro4" `
    -ShortcutName "DRTPro4"

Install-GHApp -Repo "ps81frt/WipeIt" -Dest "C:\Program Files\WipeIt" `
    -ShortcutName "WipeIt"

Install-GHApp -Repo "ps81frt/cleaner" -Dest "C:\Program Files\Cleaner" `
    -ShortcutName "Cleaner" -AllowPs1

Install-GHApp -Repo "ps81frt/KB-Manager" -Dest "C:\Program Files\KB-Manager" `
    -ShortcutName "KB-Manager"

Install-GHApp -Repo "ps81frt/SANAPP-Forensic-Scanner-Pro" `
    -Dest "C:\Program Files\SANAPP-Forensic-Scanner-Pro" `
    -ShortcutName "SANAPP Forensic Scanner Pro" -AllowPs1
$sanapPath = "C:\Program Files\SANAPP-Forensic-Scanner-Pro\Sanapp"
$currentPath = [Environment]::GetEnvironmentVariable("Path", $pathType)
if ($currentPath -notlike "*$sanapPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$sanapPath", $pathType)
    Write-Host "  [OK] PATH SANAPP -> $sanapPath" -ForegroundColor Green
    "[$(Get-Date)] PATH updated $sanapPath" | Out-File $log -Append
}

$dest = "C:\Program Files\VScode_backup"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
if (Test-Path "$dest\vscode_backuper.ps1") {
    Write-Host "[SKIP] VScode_backup deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP VScode_backup already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Installation VScode_backup..." -ForegroundColor Yellow
    "[$(Get-Date)] START VScode_backup" | Out-File $log -Append

    $vscBackupBase = "https://raw.githubusercontent.com/ps81frt/VScode_backup/refs/heads/main"
    New-Item -ItemType Directory -Force -Path "$dest\VSCode-Backup" | Out-Null
    DlFile "$vscBackupBase/vscode_backuper.ps1"             "$dest\vscode_backuper.ps1"
    DlFile "$vscBackupBase/VSCode-Backup/settings.json"     "$dest\VSCode-Backup\settings.json"
    DlFile "$vscBackupBase/VSCode-Backup/extensions.txt"    "$dest\VSCode-Backup\extensions.txt"

    $lnk = $shell.CreateShortcut("$startMenu\VScode_backup.lnk")
    $lnk.TargetPath       = "powershell.exe"
    $lnk.Arguments        = "-ExecutionPolicy Bypass -File `"$dest\vscode_backuper.ps1`""
    $lnk.WorkingDirectory = $dest
    $lnk.Save()
    "[$(Get-Date)] INSTALLED VScode_backup tool" | Out-File $log -Append
}

$vscUserDir = "$env:APPDATA\Code\User"
New-Item -ItemType Directory -Force -Path $vscUserDir | Out-Null
if (Test-Path "$dest\VSCode-Backup\settings.json") {
    Copy-Item "$dest\VSCode-Backup\settings.json" "$vscUserDir\settings.json" -Force
    Write-Host "  [OK] VSCode settings.json restaure" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED VSCode settings.json restored" | Out-File $log -Append
}
if (Test-Path "$dest\VSCode-Backup\extensions.txt") {
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if ($codeCmd) {
        $extensions = Get-Content "$dest\VSCode-Backup\extensions.txt" | Where-Object { $_ -match '\S' }
        foreach ($ext in $extensions) {
            Write-Host "  [...]  Extension $ext..." -ForegroundColor Yellow
            & code --install-extension $ext --force 2>$null | Out-Null
        }
        Write-Host "  [OK] $($extensions.Count) extensions VSCode installees" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED VSCode $($extensions.Count) extensions" | Out-File $log -Append
    } else {
        Write-Host "  [SKIP] code non trouve dans PATH, extensions non installees" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP VSCode extensions code not in PATH" | Out-File $log -Append
    }
}
Write-Host "[OK] VScode_backup installe" -ForegroundColor Green

$r = Get-GHRelease "ps81frt/hciconf-W"
$dest = "C:\Program Files\hciconf-W"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$asset = Get-GHAsset $r "\.(exe|zip)$"
if ($asset) {
    $dl = "$env:TEMP\$($asset.name)"
    Write-Host "[...] Telechargement hciconf-W..." -ForegroundColor Yellow
    "[$(Get-Date)] START hciconf-W" | Out-File $log -Append
    DlFile $asset.browser_download_url $dl
    if ($asset.name -match "\.zip$") {
        Expand-Archive $dl -DestinationPath $dest -Force
        $exe = Get-ChildItem $dest -Filter "*.exe" -Recurse | Select-Object -First 1
        if (-not $exe) {
            $modInstalled = (Test-Path "$env:USERPROFILE\Documents\PowerShell\Modules\hciconfig\hciconfig.psm1") -or
                            (Test-Path "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\hciconfig\hciconfig.psm1")
            if ($modInstalled) {
                Write-Host "[SKIP] hciconf-W : pas d'exe dans la release, module PS deja installe" -ForegroundColor Cyan
                "[$(Get-Date)] SKIP hciconf-W tool no exe in release, PS module already installed" | Out-File $log -Append
            } else {
                $contents = (Get-ChildItem $dest -Recurse | Select-Object -ExpandProperty Name) -join ", "
                Write-Host "[ERREUR] hciconf-W tool exe non trouve apres install. Contenu : $contents" -ForegroundColor Red
                "[$(Get-Date)] ERROR hciconf-W tool exe not found. Contents: $contents" | Out-File $log -Append
            }
        } else {
            New-Shortcut "hciconf-W" $exe.FullName $exe.DirectoryName
            Write-Host "[OK] hciconf-W tool installe" -ForegroundColor Green
            "[$(Get-Date)] INSTALLED hciconf-W tool" | Out-File $log -Append
        }
    } else {
        Copy-Item $dl "$dest\$($asset.name)" -Force
        $exe = Get-Item "$dest\$($asset.name)"
        New-Shortcut "hciconf-W" $exe.FullName $exe.DirectoryName
        Write-Host "[OK] hciconf-W tool installe" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED hciconf-W tool" | Out-File $log -Append
    }
    Remove-Item $dl -ErrorAction SilentlyContinue
} else {
    $modInstalled = (Test-Path "$env:USERPROFILE\Documents\PowerShell\Modules\hciconfig\hciconfig.psm1") -or
                    (Test-Path "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\hciconfig\hciconfig.psm1")
    if ($modInstalled) {
        Write-Host "[SKIP] hciconf-W : aucun asset release, module PS present" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP hciconf-W no release asset, PS module present" | Out-File $log -Append
    } else {
        Write-Host "[ERREUR] hciconf-W : aucun asset release et module PS absent" -ForegroundColor Red
        "[$(Get-Date)] ERROR hciconf-W no release asset and PS module missing" | Out-File $log -Append
    }
}

$moduleRoot = "$HOME\Documents\PowerShell\Modules\Start-UsbDaemon"
if (Test-Path "$moduleRoot\Start-UsbDaemon.psm1") {
    Write-Host "[SKIP] Start-UsbDaemon deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP Start-UsbDaemon already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Installation Start-UsbDaemon..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
    DlFile "https://raw.githubusercontent.com/ps81frt/Start-UsbDaemon/main/Start-UsbDaemon.psm1" "$moduleRoot\Start-UsbDaemon.psm1"
    DlFile "https://raw.githubusercontent.com/ps81frt/Start-UsbDaemon/main/Start-UsbDaemon.psd1" "$moduleRoot\Start-UsbDaemon.psd1"
    Write-Host "[OK] Start-UsbDaemon installe" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED Start-UsbDaemon Module" | Out-File $log -Append
}

$modulePath = "$HOME\Documents\PowerShell\Modules\pastebinit"
if (Test-Path "$modulePath\pastebinit.psm1") {
    Write-Host "[SKIP] pastebinit PS7 deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP pastebinit PS7 already installed" | Out-File $log -Append
} else {
    New-Item -ItemType Directory -Force -Path $modulePath | Out-Null
    DlFile "https://raw.githubusercontent.com/ps81frt/paste-binit/main/pastebinit.psm1" "$modulePath\pastebinit.psm1"
    Write-Host "[OK] pastebinit PS7 installe" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED pastebinit Module (PS7 Path)" | Out-File $log -Append
}

}

# ============================================================
# PROFIL POWERSHELL + VIMRC (DOTFILES)
# ============================================================

if ($RUN_DOTFILES) {

$profileDir = "$env:USERPROFILE\Documents\PowerShell"
if (!(Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

$profileURL  = "https://raw.githubusercontent.com/ps81frt/Windows_Dotfiles/main/Vanilla/Microsoft.PowerShell_profile.ps1"
$profileDest = "$profileDir\Microsoft.PowerShell_profile.ps1"
if (Test-Path $profileDest) {
    Write-Host "[SKIP] Profil PowerShell deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP PowerShell Profile already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Telechargement profil PowerShell..." -ForegroundColor Yellow
    DlFile $profileURL $profileDest
    if (Test-Path $profileDest) {
        Write-Host "[OK] Profil PowerShell installe" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED PowerShell Profile" | Out-File $log -Append
    } else {
        Write-Host "[ERREUR] Profil PowerShell non telecharge" -ForegroundColor Red
        "[$(Get-Date)] ERROR PowerShell Profile download failed" | Out-File $log -Append
    }
}

$vimrcURL  = "https://raw.githubusercontent.com/ps81frt/Windows_Dotfiles/main/Vanilla/_vimrc"
$vimrcDest = "$env:USERPROFILE\_vimrc"
if (Test-Path $vimrcDest) {
    Write-Host "[SKIP] _vimrc deja installe" -ForegroundColor Cyan
    "[$(Get-Date)] SKIP _vimrc already installed" | Out-File $log -Append
} else {
    Write-Host "[...] Telechargement _vimrc..." -ForegroundColor Yellow
    DlFile $vimrcURL $vimrcDest
    if (Test-Path $vimrcDest) {
        Write-Host "[OK] _vimrc installe" -ForegroundColor Green
        "[$(Get-Date)] INSTALLED _vimrc" | Out-File $log -Append
    } else {
        Write-Host "[ERREUR] _vimrc non telecharge" -ForegroundColor Red
        "[$(Get-Date)] ERROR _vimrc download failed" | Out-File $log -Append
    }
}

}

# ============================================================
# HARDENING & SERVICES
# ============================================================

if ($RUN_HARDENING) {

$port = 55555
Write-Host "[...] Configuration port RDP -> $port" -ForegroundColor Yellow
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "PortNumber" -Value $port
New-NetFirewallRule -DisplayName "RDP port $port" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction SilentlyContinue | Out-Null
Restart-Service "TermService" -Force -ErrorAction SilentlyContinue
Write-Host "[OK] Port RDP $port configure" -ForegroundColor Green
Write-Host "[...] Desactivation SMB1..." -ForegroundColor Yellow
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] SMB1 desactive" -ForegroundColor Green
"[$(Get-Date)] DISABLED SMB1" | Out-File $log -Append
$servicesToDisable = @("RemoteRegistry", "WSearch", "Spooler")
Write-Host "[...] Desactivation services inutiles..." -ForegroundColor Yellow
foreach ($svc in $servicesToDisable) {
    if (Get-Service $svc -ErrorAction SilentlyContinue) {
        Set-Service $svc -StartupType Disabled
        Stop-Service $svc -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Service $svc desactive" -ForegroundColor Green
        "[$(Get-Date)] DISABLED service $svc" | Out-File $log -Append
    }
}

Disable-ScheduledTask -TaskName "npcapwatchdog" -ErrorAction SilentlyContinue | Out-Null

}


# ========================================================
# LOCKSCREEN
# ============================================================

if ($RUN_LOCKSCREEN) {

Write-Host "[...] Configuration LockScreen..." -ForegroundColor Yellow
"[$(Get-Date)] START LockScreen" | Out-File $log -Append

$lsDir       = "C:\LockScreen"
$lsSrc       = "$PSScriptRoot\LockScreen"
$lsImgPath   = "$lsDir\backgroundDefault.jpg"
$lsRawSource = "$lsDir\ps81frt.png"
$lsRegPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

New-Item -ItemType Directory -Path $lsDir -Force | Out-Null
Copy-Item "$lsSrc\*" $lsDir -Force
"[$(Get-Date)] OK LockScreen files copied" | Out-File $log -Append

if (Test-Path $lsRawSource) {
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    if (-not $magick) {
        $magickExe = Get-ChildItem "C:\Program Files" -Filter "magick.exe" -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
        if ($magickExe) { $magick = $magickExe }
    }
    if ($magick) {
        $magickCmd = if ($magick -is [System.Management.Automation.CommandInfo]) { $magick.Source } else { $magick.FullName }
        Write-Host "[...] LockScreen redimensionnement..." -ForegroundColor Yellow
        & $magickCmd "$lsRawSource" -resize 1920x1080 -strip -interlace none -colorspace sRGB -quality 75 "$lsImgPath"
        if (Test-Path $lsImgPath) {
            Write-Host "[OK] LockScreen image redimensionnee" -ForegroundColor Green
            "[$(Get-Date)] OK LockScreen magick $lsRawSource -> $lsImgPath" | Out-File $log -Append
        } else {
            Write-Host "[ERREUR] LockScreen magick echoue" -ForegroundColor Red
            "[$(Get-Date)] ERROR LockScreen magick failed" | Out-File $log -Append
        }
    } else {
        Write-Host "[SKIP] LockScreen magick absent" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP LockScreen magick not found" | Out-File $log -Append
    }
}

if (!(Test-Path $lsRegPath)) { New-Item -Path $lsRegPath -Force | Out-Null }
Set-ItemProperty -Path $lsRegPath -Name "LockScreenImageStatus" -Value 1          -Type DWord  -Force
Set-ItemProperty -Path $lsRegPath -Name "LockScreenImagePath"   -Value $lsImgPath -Type String -Force
Set-ItemProperty -Path $lsRegPath -Name "LockScreenImageUrl"    -Value $lsImgPath -Type String -Force

if (Test-Path $lsImgPath) {
    Write-Host "[OK] LockScreen configure" -ForegroundColor Green
    "[$(Get-Date)] INSTALLED LockScreen $lsImgPath" | Out-File $log -Append
} else {
    Write-Host "[ERREUR] LockScreen image absente : $lsImgPath" -ForegroundColor Red
    "[$(Get-Date)] ERROR LockScreen image missing $lsImgPath" | Out-File $log -Append
}

}

# ============================================================
# BACKGROUND
# ============================================================

if ($RUN_BACKGROUND) {

    Write-Host "[...] Configuration Background..." -ForegroundColor Yellow
    "[$(Get-Date)] START Background" | Out-File $log -Append

    $lsDir     = "C:\LockScreen"
    $bgGPO     = $true                       # true = force HKLM (tous users, non modifiable) | false = HKCU (user courant, modifiable)
    $bgFile    = "backgroundDefault.jpg"    # <- nom du fichier background dans LockScreen\
    $bgImg     = "$lsDir\$bgFile"
    $bgRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

    if (Test-Path $bgImg) {
        if ($bgGPO) {
            Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue
            if (!(Test-Path $bgRegPath)) { New-Item -Path $bgRegPath -Force | Out-Null }
            Set-ItemProperty -Path $bgRegPath -Name "DesktopImageStatus" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $bgRegPath -Name "DesktopImagePath" -Value $bgImg -Type String -Force
            Set-ItemProperty -Path $bgRegPath -Name "DesktopImageUrl" -Value $bgImg -Type String -Force
            Write-Host "[OK] Background configure (GPO - non modifiable)" -ForegroundColor Green
            "[$(Get-Date)] INSTALLED Background GPO $bgImg" | Out-File $log -Append
        } else {
            Remove-ItemProperty -Path $bgRegPath -Name "DesktopImageStatus" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $bgRegPath -Name "DesktopImagePath" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $bgRegPath -Name "DesktopImageUrl" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -Value $bgImg -Force
            $wallpaperSource = @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(int a, int b, string c, int d);
}
'@
            Add-Type -TypeDefinition $wallpaperSource
            [Wallpaper]::SystemParametersInfo(0x0014, 0, $bgImg, 0x01 -bor 0x02) | Out-Null
            Write-Host "[OK] Background configure (user - modifiable)" -ForegroundColor Green
            "[$(Get-Date)] INSTALLED Background user $bgImg" | Out-File $log -Append
        }
        RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters 1, True
        Start-Sleep -Seconds 1
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        Start-Process explorer
    } else {
        Write-Host "[SKIP] Background image absente : $bgImg" -ForegroundColor Cyan
        "[$(Get-Date)] SKIP Background image missing $bgImg" | Out-File $log -Append
    }
}

# ============================================================
# REFRESH PATH SESSION COURANTE
# ============================================================

$machinePath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
$userPath    = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
$env:Path    = "$machinePath;$userPath"
Write-Host "[OK] PATH session courante rafraichi" -ForegroundColor Green
"[$(Get-Date)] OK PATH session refreshed" | Out-File $log -Append

# ============================================================
# RAPPORT FINAL
# ============================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$adminLabel = if ($isAdmin) { "OUI" } else { "NON (ATTENTION)" }
$adminColor = if ($isAdmin) { "Green" } else { "Red" }
"[$(Get-Date)] RAPPORT MACHINE=$env:COMPUTERNAME USER=$env:USERNAME ADMIN=$adminLabel" | Out-File $log -Append
"[$(Get-Date)] DONE - Full Execution Completed" | Out-File $log -Append

$logLines  = Get-Content $log -ErrorAction SilentlyContinue
$installed = $logLines | Where-Object { $_ -match '^\[.*\] (OK|INSTALLED)' }
$skipped   = $logLines | Where-Object { $_ -match '^\[.*\] SKIP' }
$errors    = $logLines | Where-Object { $_ -match '^\[.*\] ERROR' }
$warns     = $logLines | Where-Object { $_ -match '^\[.*\] WARN' }
$paths     = $logLines | Where-Object { $_ -match 'PATH updated' }
$dateEnd   = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
$envPath   = [Environment]::GetEnvironmentVariable("Path", "Machine")
$sys32ok   = if ($envPath -like "*C:\Windows\System32*") { "OUI" } else { "NON" }

# ── Console ──────────────────────────────────────────────────
Write-Host "`n$("=" * 60)" -ForegroundColor Cyan
Write-Host "  RAPPORT FINAL - $env:COMPUTERNAME - $env:USERNAME" -ForegroundColor Cyan
Write-Host "$("=" * 60)" -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor White
Write-Host "  User       : $env:USERNAME" -ForegroundColor White
Write-Host "  Admin      : $adminLabel" -ForegroundColor $adminColor
Write-Host "  System32   : $sys32ok" -ForegroundColor White
Write-Host "  Log        : $log" -ForegroundColor White
Write-Host "  Date fin   : $dateEnd" -ForegroundColor White
Write-Host "$("=" * 60)" -ForegroundColor Cyan

Write-Host "`n[OK] Installes ($($installed.Count)) :" -ForegroundColor Green
$installed | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }

if ($skipped) {
    Write-Host "`n[--] Skips ($($skipped.Count)) :" -ForegroundColor Cyan
    $skipped | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
}

if ($paths) {
    Write-Host "`n[*] PATH mis a jour :" -ForegroundColor Yellow
    $paths | ForEach-Object { Write-Host "  $($_ -replace '^\[[^\]]+\] ','')" -ForegroundColor Yellow }
}

if ($warns) {
    Write-Host "`n[!] Avertissements ($($warns.Count)) :" -ForegroundColor Yellow
    $warns | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

if ($errors) {
    Write-Host "`n[!!] Erreurs ($($errors.Count)) :" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
    Write-Host "`n[OK] Aucune erreur detectee" -ForegroundColor Green
}

Write-Host "`n$("=" * 60)" -ForegroundColor Cyan
Write-Host "  Log complet : $log" -ForegroundColor Cyan
Write-Host "$("=" * 60)`n" -ForegroundColor Cyan

# ── Export TXT ───────────────────────────────────────────────
$reportPath = "$PSScriptRoot\install-report.txt"
$report = @"
================================================
  RAPPORT POST-INSTALL
  Machine  : $env:COMPUTERNAME
  User     : $env:USERNAME
  Admin    : $adminLabel
  System32 : $sys32ok
  Date     : $dateEnd
  Log      : $log
================================================

--- INSTALLES ($($installed.Count)) ---
$($installed -join "`n")

--- SKIPS ($($skipped.Count)) ---
$($skipped -join "`n")

--- PATH MIS A JOUR ---
$($paths -join "`n")

--- AVERTISSEMENTS ($($warns.Count)) ---
$($warns -join "`n")

--- ERREURS ($($errors.Count)) ---
$($errors -join "`n")

================================================
  FIN DU RAPPORT
================================================
"@
$report | Out-File $reportPath -Encoding UTF8
Write-Host "  [OK] Rapport exporte : $reportPath" -ForegroundColor Green
