. "$PSScriptRoot\..\src\Ranger-Telechargements.ps1"

Describe 'Get-Categorie' {
    It 'range une extension connue' { Get-Categorie -Extension '.pdf' | Should Be 'Documents' }
    It 'ignore la casse'           { Get-Categorie -Extension '.JPG' | Should Be 'Images' }
    It 'accepte sans point'        { Get-Categorie -Extension 'mp4'  | Should Be 'Vidéos' }
    It 'range une double extension par la dernière' {
        Get-Categorie -Extension ([IO.Path]::GetExtension('backup.tar.gz')) | Should Be 'Archives'
    }
    It 'envoie l''inconnu dans Autres' { Get-Categorie -Extension '.xyz' | Should Be 'Autres' }
    It 'envoie le vide dans Autres'    { Get-Categorie -Extension ''     | Should Be 'Autres' }
}

Describe 'Test-FichierAIgnorer' {
    It 'ignore un téléchargement en cours' {
        $f = New-Item -ItemType File -Path 'TestDrive:\film.mp4.crdownload'
        Test-FichierAIgnorer -Fichier $f | Should Be $true
    }
    It 'ignore un fichier caché' {
        $f = New-Item -ItemType File -Path 'TestDrive:\cache.txt'
        $f.Attributes = 'Hidden'
        Test-FichierAIgnorer -Fichier $f | Should Be $true
    }
    It 'ignore le journal' {
        $f = New-Item -ItemType File -Path 'TestDrive:\rangement.log'
        Test-FichierAIgnorer -Fichier $f | Should Be $true
    }
    It 'garde un fichier normal' {
        $f = New-Item -ItemType File -Path 'TestDrive:\note.txt'
        Test-FichierAIgnorer -Fichier $f | Should Be $false
    }
}

Describe 'Get-CheminLibre' {
    It 'garde le nom s''il est libre' {
        Get-CheminLibre -Dossier 'TestDrive:\' -Nom 'a.pdf' | Should Be (Join-Path 'TestDrive:\' 'a.pdf')
    }
    It 'ajoute (2) en cas de conflit' {
        New-Item -ItemType File -Path 'TestDrive:\b.pdf' | Out-Null
        Get-CheminLibre -Dossier 'TestDrive:\' -Nom 'b.pdf' | Should Be (Join-Path 'TestDrive:\' 'b (2).pdf')
    }
    It 'passe à (3) si (2) est pris' {
        New-Item -ItemType File -Path 'TestDrive:\c.pdf', 'TestDrive:\c (2).pdf' | Out-Null
        Get-CheminLibre -Dossier 'TestDrive:\' -Nom 'c.pdf' | Should Be (Join-Path 'TestDrive:\' 'c (3).pdf')
    }
    It 'gère un fichier sans extension' {
        New-Item -ItemType File -Path 'TestDrive:\LISEZMOI' | Out-Null
        Get-CheminLibre -Dossier 'TestDrive:\' -Nom 'LISEZMOI' | Should Be (Join-Path 'TestDrive:\' 'LISEZMOI (2)')
    }
}

Describe 'Invoke-Rangement' {
    It 'range les fichiers par type' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\tri'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.JPG", "$s\c.xyz" | Out-Null
        $r = Invoke-Rangement -Source $s
        "$s\Documents\a.pdf" | Should Exist
        "$s\Images\b.JPG"   | Should Exist
        "$s\Autres\c.xyz"   | Should Exist
        $r.Comptes['Documents'] | Should Be 1
        $r.Erreurs.Count | Should Be 0
    }
    It 'laisse les téléchargements en cours et les sous-dossiers' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\encours'
        New-Item -ItemType File -Path "$s\x.crdownload" | Out-Null
        New-Item -ItemType Directory -Path "$s\Perso" | Out-Null
        New-Item -ItemType File -Path "$s\Perso\y.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        "$s\x.crdownload" | Should Exist
        "$s\Perso\y.pdf"  | Should Exist
    }
    It 'n''écrase pas un fichier existant' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\conflit'
        New-Item -ItemType Directory -Path "$s\Documents" | Out-Null
        Set-Content -LiteralPath "$s\Documents\a.pdf" -Value 'ancien'
        Set-Content -LiteralPath "$s\a.pdf" -Value 'nouveau'
        Invoke-Rangement -Source $s | Out-Null
        Get-Content -LiteralPath "$s\Documents\a.pdf"     | Should Be 'ancien'
        Get-Content -LiteralPath "$s\Documents\a (2).pdf" | Should Be 'nouveau'
    }
    It 'range un nom avec crochets' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\crochets'
        New-Item -ItemType File -Path "$s\photo[1].jpg" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        Test-Path -LiteralPath "$s\Images\photo[1].jpg" | Should Be $true
    }
    It 'range un nom accentué et le journalise' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\accents'
        New-Item -ItemType File -Path "$s\Facture été.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        "$s\Documents\Facture été.pdf" | Should Exist
        "$s\rangement.log" | Should Exist
        (Get-Content -LiteralPath "$s\rangement.log" -Encoding UTF8) -match 'déplacé \| Facture été\.pdf -> Documents\\Facture été\.pdf' | Should Not BeNullOrEmpty
    }
    It 'continue si un fichier est verrouillé' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\verrou'
        New-Item -ItemType File -Path "$s\ouvert.pdf", "$s\libre.pdf" | Out-Null
        $flux = [IO.File]::Open((Join-Path (Convert-Path $s) 'ouvert.pdf'), 'Open', 'Read', 'None')
        try { $r = Invoke-Rangement -Source $s } finally { $flux.Close() }
        "$s\ouvert.pdf"          | Should Exist
        "$s\Documents\libre.pdf" | Should Exist
        $r.Erreurs.Count | Should Be 1
    }
    It 'ne fait rien sur un dossier vide' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\vide'
        $r = Invoke-Rangement -Source $s
        $r.Comptes.Count | Should Be 0
        $r.Erreurs.Count | Should Be 0
    }
}
