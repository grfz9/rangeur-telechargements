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
