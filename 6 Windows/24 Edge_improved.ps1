# Vérification des privilèges d'administrateur
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "Ce script nécessite des privilèges d'administrateur. Relancement en tant qu'administrateur..."
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

# Configuration de l'interface utilisateur
$Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + " (Administrator)"
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.PrivateData.ProgressBackgroundColor = "Black"
$Host.PrivateData.ProgressForegroundColor = "White"
Clear-Host

# Fonction pour télécharger des fichiers avec vérification de hachage
function Get-FileFromWeb {
    param (
        [Parameter(Mandatory)][string]$URL,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$ExpectedHash
    )
    try {
        Invoke-WebRequest -Uri $URL -OutFile $File
        $actualHash = (Get-FileHash -Path $File -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedHash) {
            throw "Le hachage du fichier téléchargé ne correspond pas au hachage attendu."
        }
    } catch {
        Write-Host "Erreur lors du téléchargement du fichier : $_"
        Exit
    }
}

# Menu principal
Write-Host "1. Désinstaller Microsoft Edge"
Write-Host "2. Installer/Mettre à jour Microsoft Edge"
while ($true) {
    $choice = Read-Host "Veuillez choisir une option (1-2)"
    if ($choice -match '^[1-2]$') {
        switch ($choice) {
            1 { Uninstall-Edge }
            2 { Install-Edge }
        }
    } else {
        Write-Host "Entrée invalide. Veuillez sélectionner une option valide (1-2)."
    }
}

# Fonction pour désinstaller Edge
function Uninstall-Edge {
    Clear-Host
    Write-Host "Désinstallation de Microsoft Edge..."

    # Arrêter les processus liés à Edge
    $stop = "MicrosoftEdgeUpdate", "OneDrive", "WidgetService", "Widgets", "msedge", "msedgewebview2"
    $stop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

    # Désinstaller le package Copilot
    Get-AppxPackage -allusers *Microsoft.Windows.Ai.Copilot.Provider* | Remove-AppxPackage

    # Modifier les clés de registre pour empêcher les mises à jour et permettre la désinstallation
    reg add "HKLM\SOFTWARE\Microsoft\EdgeUpdate" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d "1" /f | Out-Null
    reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" /v "AllowUninstall" /t REG_SZ /f | Out-Null

    # Créer un nouveau dossier et fichier pour désinstaller Edge
    New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType File -Name "MicrosoftEdge.exe" -ErrorAction SilentlyContinue | Out-Null

    # Trouver la chaîne de désinstallation de Edge
    $regview = [Microsoft.Win32.RegistryView]::Registry32
    $microsoft = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regview).OpenSubKey("SOFTWARE\Microsoft", $true)
    $uninstallregkey = $microsoft.OpenSubKey("Windows\CurrentVersion\Uninstall\Microsoft Edge")
    try {
        $uninstallstring = $uninstallregkey.GetValue("UninstallString") + " --force-uninstall"
    } catch {
        Write-Host "Impossible de trouver la chaîne de désinstallation de Edge."
        Exit
    }

    # Désinstaller Edge
    Start-Process cmd.exe "/c $uninstallstring" -WindowStyle Hidden -Wait

    # Supprimer le dossier et le fichier
    Remove-Item -Recurse -Force "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ErrorAction SilentlyContinue | Out-Null

    # Trouver et désinstaller EdgeUpdate
    $edgeupdate = @()
    "LocalApplicationData", "ProgramFilesX86", "ProgramFiles" | ForEach-Object {
        $folder = [Environment]::GetFolderPath($_)
        $edgeupdate += Get-ChildItem "$folder\Microsoft\EdgeUpdate\*.*.*.*\MicrosoftEdgeUpdate.exe" -rec -ea 0
    }

    # Supprimer les clés de registre liées à EdgeUpdate
    $REG = "HKCU:\SOFTWARE", "HKLM:\SOFTWARE", "HKCU:\SOFTWARE\Policies", "HKLM:\SOFTWARE\Policies", "HKCU:\SOFTWARE\WOW6432Node", "HKLM:\SOFTWARE\WOW6432Node", "HKCU:\SOFTWARE\WOW6432Node\Policies", "HKLM:\SOFTWARE\WOW6432Node\Policies"
    foreach ($location in $REG) { Remove-Item "$location\Microsoft\EdgeUpdate" -recurse -force -ErrorAction SilentlyContinue }

    # Désinstaller EdgeUpdate
    foreach ($path in $edgeupdate) {
        if (Test-Path $path) { Start-Process -Wait $path -Args "/unregsvc" | Out-Null }
        do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
        if (Test-Path $path) { Start-Process -Wait $path -Args "/uninstall" | Out-Null }
        do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
    }

    # Supprimer les clés de registre liées à EdgeWebView
    cmd /c "reg delete `"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView`" /f >nul 2>&1"
    cmd /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView`" /f >nul 2>&1"

    # Supprimer les dossiers et les raccourcis de Edge
    Remove-Item -Recurse -Force "$env:SystemDrive\Program Files (x86)\Microsoft" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:SystemDrive\Windows\System32\config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:SystemDrive\Users\Public\Desktop\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null

    Clear-Host
    Write-Host "Redémarrage nécessaire pour appliquer les modifications..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Exit
}

# Fonction pour installer/mettre à jour Edge
function Install-Edge {
    Clear-Host
    Write-Host "Installation/Mise à jour de Microsoft Edge..."

    # Arrêter les processus liés à Edge
    $stop = "MicrosoftEdgeUpdate", "OneDrive", "WidgetService", "Widgets", "msedge", "msedgewebview2"
    $stop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

    # Installer le package Copilot
    Get-AppXPackage -AllUsers *Microsoft.Windows.Ai.Copilot.Provider* | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}

    # Activer les mises à jour de Edge
    cmd /c "reg delete `"HKLM\SOFTWARE\Microsoft\EdgeUpdate`" /f >nul 2>&1"

    # Supprimer la clé de registre permettant la désinstallation de Edge
    cmd /c "reg delete `"HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev`" /f >nul 2>&1"

    # Télécharger l'installateur de Edge
    Get-FileFromWeb -URL "https://go.microsoft.com/fwlink/?linkid=2109047&Channel=Stable&language=en&brand=M100" -File "$env:TEMP\Edge.exe" -ExpectedHash "YOUR_EXPECTED_HASH_HERE"

    # Lancer l'installateur de Edge
    Start-Process -wait "$env:TEMP\Edge.exe"

    # Télécharger l'installateur de Edge WebView
    Get-FileFromWeb -URL "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/304fddef-b073-4e0a-b1ff-c2ea02584017/MicrosoftEdgeWebview2Setup.exe" -File "$env:TEMP\EdgeWebView.exe" -ExpectedHash "YOUR_EXPECTED_HASH_HERE"

    # Lancer l'installateur de Edge WebView
    Start-Process -wait "$env:TEMP\EdgeWebView.exe"

    # Créer des raccourcis pour Edge
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:SystemDrive\Windows\System32\config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()
    $Shortcut = $WshShell.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()
    $Shortcut = $WshShell.CreateShortcut("$env:SystemDrive\Users\Public\Desktop\Microsoft Edge.lnk")
    $Shortcut.TargetPath = "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Save()

    Clear-Host
    Write-Host "Redémarrage nécessaire pour appliquer les modifications..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    # Ouvrir uBlock Origin dans le navigateur
    Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://microsoftedge.microsoft.com/addons/detail/ublock-origin/odfafepnkmbhccpbejgmiehpchacaeak"
    Exit
}
