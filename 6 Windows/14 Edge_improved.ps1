# Importation des modules
Import-Module EdgeManagement

# Fonction de journalisation
function Write-Log {
    param ([string]$Message)
    $logPath = "$env:TEMP\EdgeScript.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message"
}

# Vérification des privilèges d'administrateur
function Check-Admin {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Host "Ce script nécessite des privilèges d'administrateur. Relancement en tant qu'administrateur..."
        Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit
    }
}

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
        Write-Host "Erreur lors du téléchargement du fichier : $_" -ForegroundColor Red
        Write-Log "Erreur lors du téléchargement du fichier : $_"
        Exit
    }
}

# Fonction pour désinstaller Edge
function Uninstall-Edge {
    Write-Log "Début de la désinstallation de Edge."
    Clear-Host
    Write-Host "Désinstallation de Microsoft Edge..."

    # Arrêter les processus liés à Edge
    $processes = "MicrosoftEdgeUpdate", "OneDrive", "WidgetService", "Widgets", "msedge", "msedgewebview2"
    foreach ($process in $processes) {
        if (Get-Process -Name $process -ErrorAction SilentlyContinue) {
            Stop-Process -Name $process -Force
            Write-Host "Processus $process arrêté."
        } else {
            Write-Host "Processus $process non trouvé."
        }
    }

    # Désinstaller le package Copilot
    Get-AppxPackage -allusers *Microsoft.Windows.Ai.Copilot.Provider* | Remove-AppxPackage

    # Modifier les clés de registre pour empêcher les mises à jour et permettre la désinstallation
    try {
        reg add "HKLM\SOFTWARE\Microsoft\EdgeUpdate" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d "1" /f | Out-Null
        reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" /v "AllowUninstall" /t REG_SZ /f | Out-Null
    } catch {
        Write-Host "Erreur lors de la modification du registre : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la modification du registre : $_"
    }

    # Créer un nouveau dossier et fichier pour désinstaller Edge
    try {
        New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType Directory -ErrorAction Stop | Out-Null
        New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType File -Name "MicrosoftEdge.exe" -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Erreur lors de la création du dossier/fichier : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la création du dossier/fichier : $_"
    }

    # Trouver la chaîne de désinstallation de Edge
    $regview = [Microsoft.Win32.RegistryView]::Registry32
    $microsoft = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regview).OpenSubKey("SOFTWARE\Microsoft", $true)
    $uninstallregkey = $microsoft.OpenSubKey("Windows\CurrentVersion\Uninstall\Microsoft Edge")
    try {
        $uninstallstring = $uninstallregkey.GetValue("UninstallString") + " --force-uninstall"
    } catch {
        Write-Host "Impossible de trouver la chaîne de désinstallation de Edge." -ForegroundColor Red
        Write-Log "Impossible de trouver la chaîne de désinstallation de Edge."
        Exit
    }

    # Désinstaller Edge
    try {
        Start-Process cmd.exe "/c $uninstallstring" -WindowStyle Hidden -Wait
    } catch {
        Write-Host "Erreur lors de la désinstallation de Edge : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la désinstallation de Edge : $_"
    }

    # Supprimer le dossier et le fichier
    try {
        Remove-Item -Recurse -Force "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Erreur lors de la suppression du dossier/fichier : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la suppression du dossier/fichier : $_"
    }

    # Trouver et désinstaller EdgeUpdate
    $edgeupdate = @()
    "LocalApplicationData", "ProgramFilesX86", "ProgramFiles" | ForEach-Object {
        $folder = [Environment]::GetFolderPath($_)
        $edgeupdate += Get-ChildItem "$folder\Microsoft\EdgeUpdate\*.*.*.*\MicrosoftEdgeUpdate.exe" -rec -ea 0
    }

    # Supprimer les clés de registre liées à EdgeUpdate
    $REG = "HKCU:\SOFTWARE", "HKLM:\SOFTWARE", "HKCU:\SOFTWARE\Policies", "HKLM:\SOFTWARE\Policies", "HKCU:\SOFTWARE\WOW6432Node", "HKLM:\SOFTWARE\WOW6432Node", "HKCU:\SOFTWARE\WOW6432Node\Policies", "HKLM:\SOFTWARE\WOW6432Node\Policies"
    foreach ($location in $REG) {
        try {
            Remove-Item "$location\Microsoft\EdgeUpdate" -recurse -force -ErrorAction Stop
        } catch {
            Write-Host "Erreur lors de la suppression des clés de registre : $_" -ForegroundColor Red
            Write-Log "Erreur lors de la suppression des clés de registre : $_"
        }
    }

    # Désinstaller EdgeUpdate
    foreach ($path in $edgeupdate) {
        if (Test-Path $path) {
            try {
                Start-Process -Wait $path -Args "/unregsvc" | Out-Null
            } catch {
                Write-Host "Erreur lors de la désinstallation de EdgeUpdate : $_" -ForegroundColor Red
                Write-Log "Erreur lors de la désinstallation de EdgeUpdate : $_"
            }
            do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
            if (Test-Path $path) {
                try {
                    Start-Process -Wait $path -Args "/uninstall" | Out-Null
                } catch {
                    Write-Host "Erreur lors de la désinstallation de EdgeUpdate : $_" -ForegroundColor Red
                    Write-Log "Erreur lors de la désinstallation de EdgeUpdate : $_"
                }
            }
            do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
        }
    }

    # Supprimer les clés de registre liées à EdgeWebView
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" -Name "DoNotUpdateToEdgeWithChromium" -ErrorAction Stop
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" -Name "DoNotUpdateToEdgeWithChromium" -ErrorAction Stop
    } catch {
        Write-Host "Erreur lors de la suppression des clés de registre : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la suppression des clés de registre : $_"
    }

    # Supprimer les dossiers et les raccourcis de Edge
    try {
        Remove-Item -Recurse -Force "$env:SystemDrive\Program Files (x86)\Microsoft" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:SystemDrive\Windows\System32\config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
        Remove-Item -Recurse -Force "$env:SystemDrive\Users\Public\Desktop\Microsoft Edge.lnk" -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Erreur lors de la suppression des dossiers/raccourcis : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la suppression des dossiers/raccourcis : $_"
    }

    Clear-Host
    Write-Host "Redémarrage nécessaire pour appliquer les modifications..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Log "Fin de la désinstallation de Edge."
    Exit
}

# Fonction pour installer/mettre à jour Edge
function Install-Edge {
    Write-Log "Début de l'installation/mise à jour de Edge."
    Clear-Host
    Write-Host "Installation/Mise à jour de Microsoft Edge..."

    # Arrêter les processus liés à Edge
    $processes = "MicrosoftEdgeUpdate", "OneDrive", "WidgetService", "Widgets", "msedge", "msedgewebview2"
    foreach ($process in $processes) {
        if (Get-Process -Name $process -ErrorAction SilentlyContinue) {
            Stop-Process -Name $process -Force
            Write-Host "Processus $process arrêté."
        } else {
            Write-Host "Processus $process non trouvé."
        }
    }

    # Installer le package Copilot
    Get-AppXPackage -AllUsers *Microsoft.Windows.Ai.Copilot.Provider* | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}

    # Activer les mises à jour de Edge
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate" -Name "DoNotUpdateToEdgeWithChromium" -ErrorAction Stop
    } catch {
        Write-Host "Erreur lors de la modification du registre : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la modification du registre : $_"
    }

    # Supprimer la clé de registre permettant la désinstallation de Edge
    try {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" -Name "AllowUninstall" -ErrorAction Stop
    } catch {
        Write-Host "Erreur lors de la modification du registre : $_" -ForegroundColor Red
        Write-Log "Erreur lors de la modification du registre : $_"
    }

    # Télécharger l'installateur de Edge
    Get-FileFromWeb -URL "https://go.microsoft.com/fwlink/?linkid=2109047&Channel=Stable&language=en&brand=M100" -File "$env:TEMP\Edge.exe" -ExpectedHash "YOUR_EXPECTED_HASH_HERE"

    # Lancer l'installateur de Edge
    try {
        Start-Process -wait "$env:TEMP\Edge.exe"
    } catch {
        Write-Host "Erreur lors de l'installation de Edge : $_" -ForegroundColor Red
        Write-Log "Erreur lors de l'installation de Edge : $_"
    }

    # Télécharger l'installateur de Edge WebView
    Get-FileFromWeb -URL "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/304fddef-b073-4e0a-b1ff-c2ea02584017/MicrosoftEdgeWebview2Setup.exe" -File "$env:TEMP\EdgeWebView.exe" -ExpectedHash "YOUR_EXPECTED_HASH_HERE"

    # Lancer l'installateur de Edge WebView
    try {
        Start-Process -wait "$env:TEMP\EdgeWebView.exe"
    } catch {
        Write-Host "Erreur lors de l'installation de Edge WebView : $_" -ForegroundColor Red
        Write-Log "Erreur lors de l'installation de Edge WebView : $_"
    }

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
    try {
        Start-Process "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" "https://microsoftedge.microsoft.com/addons/detail/ublock-origin/odfafepnkmbhccpbejgmiehpchacaeak"
    } catch {
        Write-Host "Erreur lors de l'ouverture de la page uBlock Origin : $_" -ForegroundColor Red
        Write-Log "Erreur lors de l'ouverture de la page uBlock Origin : $_"
    }

    Write-Log "Fin de l'installation/mise à jour de Edge."
    Exit
}

# Menu principal
Write-Log "Début du script."
Check-Admin
Write-Host "1. Désinstaller Edge"
Write-Host "2. Installer/Mettre à jour Edge"
Write-Host "Q. Quitter"
while ($true) {
    $choice = Read-Host " "
    switch ($choice.ToLower()) {
        '1' { Uninstall-Edge }
        '2' { Install-Edge }
        'q' { exit }
        default { Write-Host "Entrée invalide. Veuillez choisir 1, 2 ou Q." -ForegroundColor Red }
    }
}
