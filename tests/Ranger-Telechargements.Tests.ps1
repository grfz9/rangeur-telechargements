. "$PSScriptRoot\..\src\Ranger-Telechargements.ps1"
# Les tests utilisent toujours la table par défaut, même si un
# categories.json personnalisé existe à côté du script.
$Categories = Copy-Categories $CategoriesParDefaut

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
    It 'ignore le fichier vide créé par Firefox à côté du .part' {
        $f = New-Item -ItemType File -Path 'TestDrive:\facture.pdf'
        New-Item -ItemType File -Path 'TestDrive:\facture.pdf.part' | Out-Null
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

Describe 'Get-MessageFinal' {
    It 'renvoie le résumé après un rangement' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\final'
        New-Item -ItemType File -Path "$s\a.pdf" | Out-Null
        Get-MessageFinal -Source $s | Should Be '1 fichier(s) rangé(s) : 1 Documents'
    }
    It 'renvoie un message d''erreur si le dossier est introuvable' {
        Get-MessageFinal -Source 'TestDrive:\absent' | Should Match '^Le rangement a échoué : '
    }
}

Describe 'Format-Resume' {
    It 'annonce un dossier propre' {
        $r = [pscustomobject]@{ Comptes = @{}; Erreurs = @() }
        Format-Resume -Resultat $r | Should Be 'Rien à ranger : le dossier Téléchargements est déjà propre.'
    }
    It 'liste les catégories dans l''ordre de la table' {
        $r = [pscustomobject]@{ Comptes = @{ Documents = 2; Images = 3 }; Erreurs = @() }
        Format-Resume -Resultat $r | Should Be '5 fichier(s) rangé(s) : 3 Images, 2 Documents'
    }
    It 'signale les erreurs' {
        $r = [pscustomobject]@{ Comptes = @{ Images = 1 }; Erreurs = @('a.pdf : verrouillé') }
        Format-Resume -Resultat $r | Should Be "1 fichier(s) rangé(s) : 1 Images`r`n1 fichier(s) non déplacé(s), voir rangement.log."
    }
}

Describe 'Catégories' {
    It 'lit un fichier valide en gardant l''ordre' {
        Set-Content -LiteralPath 'TestDrive:\c1.json' -Encoding UTF8 -Value '{"Zeta":["z"],"Alpha":["a"]}'
        $t = Read-Categories -Chemin 'TestDrive:\c1.json'
        @($t.Keys) -join ',' | Should Be 'Zeta,Alpha'
        Get-Categorie -Extension '.z' -Table $t | Should Be 'Zeta'
    }
    It 'reprend la table par défaut si le fichier manque' {
        (Read-Categories -Chemin 'TestDrive:\absent.json')['Images'] -contains 'jpg' | Should Be $true
    }
    It 'reprend la table par défaut si le JSON est invalide' {
        Set-Content -LiteralPath 'TestDrive:\c2.json' -Value '{ pas du json'
        (Read-Categories -Chemin 'TestDrive:\c2.json')['Images'] -contains 'jpg' | Should Be $true
    }
    It 'normalise les extensions' {
        $t = ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'Docs'; Extensions = ' .PDF , txt,,pdf' })
        $t['Docs'] -join ',' | Should Be 'pdf,txt'
    }
    It 'refuse un dossier vide'       { { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = ' '; Extensions = 'a' }) } | Should Throw }
    It 'refuse un caractère interdit' { { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'a/b'; Extensions = 'a' }) } | Should Throw }
    It 'refuse Autres'                { { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'autres'; Extensions = 'a' }) } | Should Throw }
    It 'refuse un dossier en double' {
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'A'; Extensions = 'a' }, [pscustomobject]@{ Dossier = 'a'; Extensions = 'b' }) } | Should Throw
    }
    It 'refuse une extension dans deux dossiers' {
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'A'; Extensions = 'x' }, [pscustomobject]@{ Dossier = 'B'; Extensions = 'X' }) } | Should Throw
    }
    It 'relit ce qui a été enregistré' {
        $t = ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'Vidéos'; Extensions = 'mp4' })
        Save-Categories -Chemin 'TestDrive:\c3.json' -Table $t
        (Read-Categories -Chemin 'TestDrive:\c3.json')['Vidéos'] -join ',' | Should Be 'mp4'
    }
}

Describe 'Get-PlanRangement' {
    It 'liste les fichiers et catégories sans rien déplacer' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\plan'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.crdownload", "$s\rangement-dernier.json" | Out-Null
        $p = @(Get-PlanRangement -Source $s)
        $p.Count | Should Be 1
        $p[0].Nom | Should Be 'a.pdf'
        $p[0].Categorie | Should Be 'Documents'
        "$s\a.pdf" | Should Exist
    }
    It 'renvoie un tableau vide sur un dossier vide' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\planvide'
        @(Get-PlanRangement -Source $s).Count | Should Be 0
    }
}

Describe 'Fichier d''annulation' {
    It 'enregistre chaque déplacement' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\annul'
        New-Item -ItemType File -Path "$s\a.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        $j = Get-Content -LiteralPath "$s\rangement-dernier.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        @($j.Deplacements).Count | Should Be 1
        $j.Deplacements[0].De   | Should Be 'a.pdf'
        $j.Deplacements[0].Vers | Should Be 'Documents\a.pdf'
    }
    It 'garde l''ancien fichier si rien n''a bougé' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\annul2'
        Set-Content -LiteralPath "$s\rangement-dernier.json" -Value 'ancien'
        Invoke-Rangement -Source $s | Out-Null
        Get-Content -LiteralPath "$s\rangement-dernier.json" | Should Be 'ancien'
    }
}

Describe 'Undo-Rangement' {
    It 'remet les fichiers en place et efface le fichier d''annulation' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\u1'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.jpg" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        $r = Undo-Rangement -Source $s
        "$s\a.pdf" | Should Exist
        "$s\b.jpg" | Should Exist
        $r.Restaures | Should Be 2
        Test-AnnulationPossible -Source $s | Should Be $false
    }
    It 'renomme si le nom d''origine est repris' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\u2'
        Set-Content -LiteralPath "$s\a.pdf" -Value 'rangé'
        Invoke-Rangement -Source $s | Out-Null
        Set-Content -LiteralPath "$s\a.pdf" -Value 'nouveau'
        Undo-Rangement -Source $s | Out-Null
        Get-Content -LiteralPath "$s\a.pdf"     | Should Be 'nouveau'
        Get-Content -LiteralPath "$s\a (2).pdf" | Should Be 'rangé'
    }
    It 'signale un fichier introuvable' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\u3'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        Move-Item -LiteralPath "$s\Documents\a.pdf" -Destination "$s\Documents\deplace.pdf"
        $r = Undo-Rangement -Source $s
        $r.Restaures | Should Be 1
        $r.Erreurs.Count | Should Be 1
    }
    It 'continue après un fichier verrouillé' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\u4'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        $flux = [IO.File]::Open((Join-Path (Convert-Path $s) 'Documents\a.pdf'), 'Open', 'Read', 'None')
        try { $r = Undo-Rangement -Source $s } finally { $flux.Close() }
        "$s\b.pdf" | Should Exist
        $r.Erreurs.Count | Should Be 1
    }
    It 'ne fait rien au deuxième appel' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\u5'
        New-Item -ItemType File -Path "$s\a.pdf" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        Undo-Rangement -Source $s | Out-Null
        $r = Undo-Rangement -Source $s
        $r.RienAAnnuler | Should Be $true
        Format-ResumeAnnulation -Resultat $r | Should Be 'Rien à annuler.'
    }
    It 'résume une annulation avec erreur' {
        $r = [pscustomobject]@{ RienAAnnuler = $false; Restaures = 2; Erreurs = @('x') }
        Format-ResumeAnnulation -Resultat $r | Should Be "2 fichier(s) remis en place.`r`n1 fichier(s) non remis, voir rangement.log."
    }
}

Describe 'Fenêtres' {
    . "$PSScriptRoot\..\src\Rangeur-UI.ps1"
    It 'charge la fenêtre principale avec ses contrôles' {
        $w = Import-Fenetre -Chemin "$PSScriptRoot\..\src\Fenetre.xaml"
        foreach ($n in 'TxtDossier','BtnChanger','ListeApercu','BtnRanger','BtnAnnuler','BtnCategories','TxtEtat') {
            $w.FindName($n) | Should Not BeNullOrEmpty
        }
    }
    It 'charge la fenêtre des catégories avec ses contrôles' {
        $w = Import-Fenetre -Chemin "$PSScriptRoot\..\src\Categories.xaml"
        foreach ($n in 'GrilleCategories','BtnAjouter','BtnSupprimer','BtnEnregistrer','BtnFermer') {
            $w.FindName($n) | Should Not BeNullOrEmpty
        }
    }
}

Describe 'Corrections de la relecture' {
    It 'refuse un nom de dossier fait de points' {
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = '..'; Extensions = 'pdf' }) } | Should Throw
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = '.'; Extensions = 'pdf' }) } | Should Throw
    }
    It 'refuse un nom finissant par un point' {
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'Images.'; Extensions = 'jpg' }) } | Should Throw
    }
    It 'refuse un nom réservé de Windows' {
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'con'; Extensions = 'jpg' }) } | Should Throw
        { ConvertTo-TableCategories -Lignes @([pscustomobject]@{ Dossier = 'LPT1'; Extensions = 'jpg' }) } | Should Throw
    }
    It 'annule encore après un déplacement du dossier entier' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\avant'
        New-Item -ItemType File -Path "$s\a.pdf", "$s\b.jpg" | Out-Null
        Invoke-Rangement -Source $s | Out-Null
        Rename-Item -LiteralPath $s -NewName 'apres'
        $r = Undo-Rangement -Source 'TestDrive:\apres'
        $r.Restaures | Should Be 2
        'TestDrive:\apres\a.pdf' | Should Exist
        'TestDrive:\apres\b.jpg' | Should Exist
    }
}
