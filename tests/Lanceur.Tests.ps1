$Fichiers = 'Ranger-Telechargements.ps1', 'Rangeur-UI.ps1', 'Fenetre.xaml', 'Categories.xaml'

Describe 'Lanceur .exe' {
    $racine = Convert-Path 'TestDrive:\'
    $exe = Join-Path $racine 'Rangeur.exe'
    & "$PSScriptRoot\..\build\Construire-Exe.ps1" -Sortie $exe | Out-Null

    It 'se compile' {
        $exe | Should Exist
    }
    It 'installe les fichiers à l''identique sans ouvrir la fenêtre' {
        $dest = Join-Path $racine 'install'
        $p = Start-Process -FilePath $exe -ArgumentList '--sans-lancer', '--dossier-installation', "`"$dest`"" -Wait -PassThru
        $p.ExitCode | Should Be 0
        foreach ($f in $Fichiers) {
            (Get-FileHash -LiteralPath (Join-Path $dest $f)).Hash |
                Should Be (Get-FileHash -LiteralPath "$PSScriptRoot\..\src\$f").Hash
        }
    }
    It 'garde le categories.json de l''utilisateur' {
        $dest = Join-Path $racine 'install2'
        New-Item -ItemType Directory -Path $dest | Out-Null
        Set-Content -LiteralPath (Join-Path $dest 'categories.json') -Value 'perso'
        Start-Process -FilePath $exe -ArgumentList '--sans-lancer', '--dossier-installation', "`"$dest`"" -Wait | Out-Null
        Get-Content -LiteralPath (Join-Path $dest 'categories.json') | Should Be 'perso'
    }
}
