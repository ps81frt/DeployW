if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "⚠️ Ce script doit être exécuté en tant qu'Administrateur."
        exit 1
}

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$DestDir = "C:\LockScreen"
$ImgName = "backgroundDefault.jpg"
$ImgPath = Join-Path $DestDir $ImgName

if (!(Test-Path $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        Write-Host " Dossier créé : $DestDir" -ForegroundColor Yellow
}

if (!(Test-Path $ImgPath)) {
    Write-Warning " Image manquante : $ImgPath"
        Write-Host "   → Copiez votre fichier '$ImgName' dans '$DestDir' avant de verrouiller la session." -ForegroundColor Cyan
}

if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

Set-ItemProperty -Path $RegPath -Name "LockScreenImageStatus" -Value 1 -Type DWord   -Force
Set-ItemProperty -Path $RegPath -Name "LockScreenImagePath"   -Value $ImgPath -Type String -Force
Set-ItemProperty -Path $RegPath -Name "LockScreenImageUrl"    -Value $ImgPath -Type String -Force

Write-Host " Registre configuré avec succès." -ForegroundColor Green
Write-Host " Placez l'image '$ImgName' dans '$DestDir', puis faites Win + L pour tester." -ForegroundColor White
