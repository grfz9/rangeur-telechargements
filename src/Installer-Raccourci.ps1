# Crée sur le Bureau un raccourci qui ouvre la fenêtre du rangeur
# (Rangeur-UI.ps1). Un raccourci existant du même nom est remplacé.
# -ExecutionPolicy Bypass ne vaut que pour ce lancement : la configuration
# de sécurité de Windows n'est pas modifiée.

$script = Join-Path $PSScriptRoot 'Rangeur-UI.ps1'
$raccourci = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Ranger Téléchargements.lnk'

$shell = New-Object -ComObject WScript.Shell
$lien = $shell.CreateShortcut($raccourci)
$lien.TargetPath = 'powershell.exe'
$lien.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$lien.IconLocation = 'shell32.dll,45'
$lien.Save()

Write-Output "Raccourci créé : $raccourci"
