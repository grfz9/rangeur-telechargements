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
