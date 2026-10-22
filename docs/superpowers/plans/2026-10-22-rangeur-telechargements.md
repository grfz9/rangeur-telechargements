# Rangeur de Téléchargements — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un script PowerShell lancé par un raccourci du Bureau qui range les fichiers de la racine de Téléchargements dans des sous-dossiers par type, sans rien supprimer ni écraser.

**Architecture:** Un seul script `src/Ranger-Telechargements.ps1` découpé en fonctions pures et testables (catégorie, filtre, chemin libre, résumé) plus une fonction `Invoke-Rangement` qui fait les déplacements. Le bloc principal ne s'exécute que si le script est lancé directement, ce qui permet aux tests de le dot-sourcer. Un second script crée le raccourci.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4.0 (déjà installé avec Windows, rien à télécharger), git.

**Spec:** `docs/superpowers/specs/2026-10-22-rangeur-telechargements-design.md`

## Global Constraints

- Cible : Windows PowerShell 5.1 (`powershell.exe`), pas PowerShell 7.
- Tests en syntaxe Pester 3.4 : `Describe` / `It` / `Should Be`, `Should Exist`, `TestDrive:`. Pas de `BeforeAll` ni de `Should -Be`.
- Tous les `.ps1` sont enregistrés en **UTF-8 avec BOM**. Sans BOM, PowerShell 5.1 lit le fichier en ANSI et casse `Vidéos` et les messages accentués.
- Toutes les opérations sur les fichiers utilisent `-LiteralPath`, jamais `-Path`, car `[` et `]` sont des jokers.
- Aucune suppression de fichier, aucun écrasement (`Move-Item` sans `-Force`).
- Dossier par défaut : `Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'`.
- Journal : `rangement.log` à la racine de la source, en ajout, encodage UTF-8, format `yyyy-MM-dd HH:mm:ss | déplacé | <nom> -> <Catégorie>\<nom final>` ou `yyyy-MM-dd HH:mm:ss | erreur | <nom> | <message>`.
- Catégories et extensions : exactement la table de la spec (section « Catégories »).
- Extensions ignorées (téléchargements en cours) : `crdownload`, `part`, `tmp`, `partial`, `download`.
- Le code, les commentaires et les commits sont en prose normale.

## Review Focus

1. Nom avec crochets (`photo[1].jpg`) : doit être rangé normalement. Test ajouté en tâche 3.
2. Conflit en chaîne (`nom.pdf` et `nom (2).pdf` déjà présents) : le fichier devient `nom (3).pdf`. Test ajouté en tâche 2.
3. Double extension (`backup.tar.gz`) : va dans `Archives` grâce à la dernière extension. Test ajouté en tâche 1.
4. Nom accentué (`Facture été.pdf`) : rangé et journalisé correctement. Test ajouté en tâche 3.
5. Dossier déjà propre : le résumé dit qu'il n'y a rien à ranger, sans erreur. Tests ajoutés en tâches 3 et 4.

---

## Structure des fichiers

- `src/Ranger-Telechargements.ps1` : toutes les fonctions et le bloc principal.
- `src/Installer-Raccourci.ps1` : crée le raccourci sur le Bureau.
- `tests/Ranger-Telechargements.Tests.ps1` : tests Pester.

Lancer les tests (depuis la racine du projet) :
`powershell -NoProfile -Command "Invoke-Pester -Script .\tests"`

---

### Task 1: Squelette, catégories et filtre

**Files:**
- Create: `src/Ranger-Telechargements.ps1`
- Test: `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Produces:
  - `$Categories` : `[ordered]` hashtable, nom de dossier vers tableau d'extensions sans point, en minuscules.
  - `$ExtensionsEnCours` : `string[]` des extensions ignorées.
  - `Get-Categorie -Extension <string>` vers `string`. Accepte l'extension avec ou sans point, toute casse. Renvoie `'Autres'` si inconnue ou vide.
  - `Test-FichierAIgnorer -Fichier <System.IO.FileInfo>` vers `bool`. Vrai si extension en cours, attribut `Hidden` ou `System`, ou nom `rangement.log`.

- [ ] **Step 1: Initialiser le dépôt**

Run: `git init` à la racine du projet. Expected: `Initialized empty Git repository`.

- [ ] **Step 2: Écrire les tests qui échouent**

En tête du fichier de test : `. "$PSScriptRoot\..\src\Ranger-Telechargements.ps1"`.

```powershell
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
```

- [ ] **Step 3: Lancer les tests, vérifier l'échec**

Run: commande de test ci-dessus. Expected: FAIL, le script source n'existe pas.

- [ ] **Step 4: Implémenter `$Categories`, `$ExtensionsEnCours`, `Get-Categorie`, `Test-FichierAIgnorer`**

Fichier en UTF-8 avec BOM. Ajouter en bas le garde du bloc principal, vide pour l'instant :
`if ($MyInvocation.InvocationName -ne '.') { }`.

- [ ] **Step 5: Lancer les tests, vérifier le succès**

Expected: 10 tests passés, 0 échec.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: add file categories and ignore filter"
```

---

### Task 2: Chemin de destination libre

**Files:**
- Modify: `src/Ranger-Telechargements.ps1`
- Test: `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Produces: `Get-CheminLibre -Dossier <string> -Nom <string>` vers `string` (chemin complet). Renvoie `Dossier\Nom` s'il n'existe pas, sinon `Dossier\base (n).ext` avec le plus petit `n >= 2` libre. Ne crée rien.

- [ ] **Step 1: Écrire les tests qui échouent**

```powershell
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
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Expected: FAIL, `Get-CheminLibre` n'est pas reconnu.

- [ ] **Step 3: Implémenter `Get-CheminLibre`**

Utiliser `[IO.Path]::GetFileNameWithoutExtension` et `GetExtension`, et `Test-Path -LiteralPath`.

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Expected: 14 tests passés, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "feat: pick a free destination name on conflict"
```

---

### Task 3: Rangement et journal

**Files:**
- Modify: `src/Ranger-Telechargements.ps1`
- Test: `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Categorie`, `Test-FichierAIgnorer`, `Get-CheminLibre`.
- Produces: `Invoke-Rangement -Source <string> [-Journal <string>]` vers `PSCustomObject` avec :
  - `Comptes` : hashtable, catégorie vers nombre de fichiers rangés (seulement les catégories non nulles) ;
  - `Erreurs` : `string[]`, une entrée `"<nom> : <message>"` par échec.
  `-Journal` vaut par défaut `Join-Path $Source 'rangement.log'`.

Comportement : `Get-ChildItem -LiteralPath $Source -File -Force` (racine seulement, pas de `-Recurse`), saut des fichiers ignorés, création du dossier cible si absent, `Move-Item -LiteralPath ... -Destination ... -ErrorAction Stop` dans un `try/catch`. Chaque action écrit une ligne au journal avec `Add-Content -Encoding UTF8`.

- [ ] **Step 1: Écrire les tests qui échouent**

Chaque `It` crée son propre sous-dossier `TestDrive:\<cas>` pour rester indépendant.

```powershell
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
        New-Item -ItemType File -Path "$s\photo``[1``].jpg" | Out-Null
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
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Expected: FAIL, `Invoke-Rangement` n'est pas reconnu.

- [ ] **Step 3: Implémenter `Invoke-Rangement`**

`Move-Item` reçoit le chemin résolu par `Convert-Path` pour que `TestDrive:` fonctionne.

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Expected: 21 tests passés, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "feat: move root files into category folders with a log"
```

---

### Task 4: Résumé et bloc principal

**Files:**
- Modify: `src/Ranger-Telechargements.ps1`
- Test: `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-Rangement` et son objet résultat.
- Produces: `Format-Resume -Resultat <PSCustomObject>` vers `string`.

Textes exacts :
- rien rangé, pas d'erreur : `Rien à ranger : le dossier Téléchargements est déjà propre.`
- sinon : `<total> fichier(s) rangé(s) : <n> <Catégorie>, <n> <Catégorie>…` dans l'ordre de `$Categories` (ou `0 fichier(s) rangé(s).` si seules des erreurs), puis si erreurs une nouvelle ligne `<k> fichier(s) non déplacé(s), voir rangement.log.`

- [ ] **Step 1: Écrire les tests qui échouent**

```powershell
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
```

- [ ] **Step 2: Lancer les tests, vérifier l'échec**

Expected: FAIL, `Format-Resume` n'est pas reconnu.

- [ ] **Step 3: Implémenter `Format-Resume` et remplir le bloc principal**

Bloc principal : `Invoke-Rangement` sur le dossier par défaut, puis `Add-Type -AssemblyName System.Windows.Forms` et `[System.Windows.Forms.MessageBox]::Show(<résumé>, 'Rangeur de Téléchargements')`.

- [ ] **Step 4: Lancer les tests, vérifier le succès**

Expected: 24 tests passés, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "feat: show a summary dialog after sorting"
```

---

### Task 5: Raccourci sur le Bureau et essai réel

**Files:**
- Create: `src/Installer-Raccourci.ps1`

**Interfaces:**
- Consumes: le chemin de `Ranger-Telechargements.ps1`, à côté de l'installeur (`$PSScriptRoot`).
- Produces: `Ranger Téléchargements.lnk` sur le Bureau (`[Environment]::GetFolderPath('Desktop')`).

- [ ] **Step 1: Implémenter `Installer-Raccourci.ps1`**

Via `WScript.Shell` : `TargetPath` = `powershell.exe`, `Arguments` = `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<chemin absolu>\Ranger-Telechargements.ps1"`, `IconLocation` = `shell32.dll,45`. Afficher le chemin du raccourci créé.

- [ ] **Step 2: Exécuter l'installeur**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\src\Installer-Raccourci.ps1`. Expected: le raccourci existe sur le Bureau.

- [ ] **Step 3: Essai réel, avec l'accord de l'utilisateur**

Ce test touche le vrai dossier Téléchargements : demander l'accord avant. L'utilisateur double-clique le raccourci. Expected : la boîte de résumé s'affiche, la racine ne contient plus que des sous-dossiers et `rangement.log`, et le journal liste chaque déplacement.

- [ ] **Step 4: Lancer toute la suite de tests**

Expected: 24 tests passés, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: add desktop shortcut installer"
```
