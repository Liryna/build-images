﻿# https://octopus.com/downloads

Write-Host "Installing octo.exe..." -ForegroundColor Cyan

$destPath = 'C:\Tools\Octopus'

if(-not (Test-Path $destPath)) {
    New-Item $destPath -ItemType directory -Force | Out-Null
}

$zipPath = "$env:TEMP\OctopusTools.zip"
(New-Object Net.WebClient).DownloadFile('https://download.octopusdeploy.com/octopus-tools/6.2.3/OctopusTools.6.2.3.zip', $zipPath)
7z x $zipPath -aoa -o"$destPath"
del $zipPath

Add-Path $destPath
Add-SessionPath $destPath

cmd /c octo --version

Write-Host "Installed Octopus tools" -ForegroundColor Green


