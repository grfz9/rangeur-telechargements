# Rangeur — Interface graphique — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une fenêtre WPF qui affiche l'aperçu du rangement, range, annule le dernier rangement, édite les catégories et permet de choisir le dossier.

**Architecture:** Toute la logique reste dans `src/Ranger-Telechargements.ps1` (fonctions testées par Pester) : catégories lues depuis `src/categories.json`, plan de rangement, fichier d'annulation. `src/Rangeur-UI.ps1` charge deux fichiers XAML et ne fait que relier les boutons à ces fonctions.

**Tech Stack:** Windows PowerShell 5.1, WPF (PresentationFramework), Pester 3.4.0, git.

**Spec:** `docs/superpowers/specs/2026-10-22-rangeur-interface-design.md` (s'appuie sur `docs/superpowers/specs/2026-10-22-rangeur-telechargements-design.md`)

## Global Constraints

- Windows PowerShell 5.1 uniquement ; tests en syntaxe Pester 3.4 (`Should Be`, `Should Throw`, `Should Exist`, `TestDrive:`).
- Tous les `.ps1` et `.xaml` en UTF-8 avec BOM.
- `-LiteralPath` pour toute opération sur un fichier ; jamais de `-Force` sur `Move-Item`.
- Aucune suppression de fichier de l'utilisateur. Seul `rangement-dernier.json` (fichier technique) est supprimé, après une annulation.
- Noms techniques : `rangement.log`, `rangement-dernier.json`, `src/categories.json`.
- Textes exacts : `Rien à annuler.`, `<n> fichier(s) remis en place.`, `<k> fichier(s) non remis, voir rangement.log.`, `<n> fichier(s) à ranger`.
- Les 27 tests existants restent verts. Les tests forcent la table par défaut juste après le dot-source (`$Categories = Copy-Categories $CategoriesParDefaut`) pour ne pas dépendre d'un `categories.json` local.
- Commande de test : `powershell -NoProfile -Command "Invoke-Pester -Script .\tests"`.

## Review Focus

1. Fichier remis en place alors que le dossier d'origine contient de nouveau ce nom : il devient `nom (2).ext`. Test en tâche 3.
2. `categories.json` contenant du JSON invalide (édité à la main) : repli silencieux sur la table par défaut. Test en tâche 1.
3. Extension saisie avec point, espaces et majuscules (` .PDF `) : normalisée en `pdf`. Test en tâche 1.
4. Deuxième clic sur « Annuler » : `Rien à annuler.`, aucun déplacement. Test en tâche 3.
5. Rangement qui ne déplace rien : l'ancien `rangement-dernier.json` n'est pas écrasé. Test en tâche 2.

---

### Task 1: Catégories dans un fichier

**Files:** Modify `src/Ranger-Telechargements.ps1`, `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Produces:
  - `$CategoriesParDefaut` : la table actuelle, `[ordered]`.
  - `$CheminCategories = Join-Path $PSScriptRoot 'categories.json'`, et `$Categories = Read-Categories -Chemin $CheminCategories` au chargement du script.
  - `Copy-Categories <IDictionary>` vers `[ordered]` (copie profonde).
  - `Read-Categories -Chemin <string>` vers `[ordered]` dossier vers `string[]`. Copie de la table par défaut si fichier absent ou illisible.
  - `ConvertTo-TableCategories -Lignes <object[]>` (objets avec propriétés `Dossier` et `Extensions` : chaîne séparée par des virgules) vers `[ordered]`. Normalise et valide ; lève une exception au message en français si invalide.
  - `Save-Categories -Chemin <string> -Table <IDictionary>` : écrit le JSON en UTF-8.
  - `Get-Categorie -Extension <string> [-Table <IDictionary>]` : `-Table` vaut `$Categories` par défaut.

- [ ] **Step 1: Tests qui échouent**

```powershell
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
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Expected: FAIL, `Read-Categories` inconnu.
- [ ] **Step 3: Implémenter** — Caractères interdits : `[IO.Path]::GetInvalidFileNameChars()`. Lecture : `Get-Content -Raw -Encoding UTF8 | ConvertFrom-Json` puis parcours de `.PSObject.Properties` (ordre conservé), le tout dans un `try/catch` qui renvoie la table par défaut. Un fichier lisible mais invalide selon les règles est aussi remplacé par la table par défaut. Ajouter `$Categories = Copy-Categories $CategoriesParDefaut` en tête du fichier de test.
- [ ] **Step 4: Lancer, vérifier le succès** — Expected: 37 passés, 0 échec.
- [ ] **Step 5: Commit** — `feat: load categories from a JSON file`

---

### Task 2: Aperçu et fichier d'annulation

**Files:** Modify `src/Ranger-Telechargements.ps1`, `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Consumes: `Get-Categorie`, `Test-FichierAIgnorer`, `Get-CheminLibre`.
- Produces:
  - `$NomAnnulation = 'rangement-dernier.json'`, ignoré par `Test-FichierAIgnorer`.
  - `Get-PlanRangement -Source <string>` vers tableau de `[pscustomobject]@{ Nom; Chemin; Categorie }` (toujours un tableau, même vide).
  - `Invoke-Rangement` parcourt `Get-PlanRangement` ; si au moins un fichier a bougé, écrit `rangement-dernier.json` : `{ "Date": "yyyy-MM-dd HH:mm:ss", "Deplacements": [ { "De": <chemin complet>, "Vers": <chemin complet> } ] }`.

- [ ] **Step 1: Tests qui échouent**

```powershell
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
        $j.Deplacements[0].De   | Should Be (Join-Path (Convert-Path $s) 'a.pdf')
        $j.Deplacements[0].Vers | Should Be (Join-Path (Convert-Path $s) 'Documents\a.pdf')
    }
    It 'garde l''ancien fichier si rien n''a bougé' {
        $s = New-Item -ItemType Directory -Path 'TestDrive:\annul2'
        Set-Content -LiteralPath "$s\rangement-dernier.json" -Value 'ancien'
        Invoke-Rangement -Source $s | Out-Null
        Get-Content -LiteralPath "$s\rangement-dernier.json" | Should Be 'ancien'
    }
}
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Expected: FAIL, `Get-PlanRangement` inconnu.
- [ ] **Step 3: Implémenter** — JSON écrit avec `ConvertTo-Json -Depth 3`, en forçant `Deplacements` en tableau même pour un seul élément (`@(...)` dans un objet `[pscustomobject]`).
- [ ] **Step 4: Lancer, vérifier le succès** — Expected: 41 passés, 0 échec.
- [ ] **Step 5: Commit** — `feat: add sorting preview and undo record`

---

### Task 3: Annulation

**Files:** Modify `src/Ranger-Telechargements.ps1`, `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Consumes: `$NomAnnulation`, `$NomJournal`, `Get-CheminLibre`.
- Produces:
  - `Test-AnnulationPossible -Source <string>` vers `bool` (le fichier d'annulation existe).
  - `Undo-Rangement -Source <string>` vers `[pscustomobject]@{ RienAAnnuler = <bool>; Restaures = <int>; Erreurs = <string[]> }`. Journalise `restauré | <Vers relatif à Source> -> <nom remis>` ou `erreur | <nom> | <message>`. Supprime le fichier d'annulation à la fin.
  - `Format-ResumeAnnulation -Resultat <pscustomobject>` vers `string` (textes des Global Constraints, lignes séparées par `` `r`n ``).

- [ ] **Step 1: Tests qui échouent**

```powershell
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
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Expected: FAIL, `Undo-Rangement` inconnu.
- [ ] **Step 3: Implémenter** — Pour chaque déplacement : `Test-Path -LiteralPath Vers` sinon erreur « introuvable » ; destination `Get-CheminLibre -Dossier (Split-Path De) -Nom (Split-Path -Leaf De)` ; `Move-Item -ErrorAction Stop` dans un `try/catch`. Fichier d'annulation illisible : traité comme `RienAAnnuler`.
- [ ] **Step 4: Lancer, vérifier le succès** — Expected: 47 passés, 0 échec.
- [ ] **Step 5: Commit** — `feat: undo the last sorting run`

---

### Task 4: Fenêtres WPF

**Files:** Create `src/Fenetre.xaml`, `src/Categories.xaml`, `src/Rangeur-UI.ps1`; Modify `src/Installer-Raccourci.ps1`, `tests/Ranger-Telechargements.Tests.ps1`

**Interfaces:**
- Consumes: `Get-PlanRangement`, `Invoke-Rangement`, `Format-Resume`, `Test-AnnulationPossible`, `Undo-Rangement`, `Format-ResumeAnnulation`, `ConvertTo-TableCategories`, `Save-Categories`, `$Categories`, `$CheminCategories`.
- Produces:
  - `Fenetre.xaml` : `Window` avec contrôles nommés `TxtDossier` (TextBlock), `BtnChanger`, `ListeApercu` (ListView, colonnes « Fichier » liée à `Nom`, « Ira dans » liée à `Categorie`), `BtnRanger`, `BtnAnnuler`, `BtnCategories`, `TxtEtat`.
  - `Categories.xaml` : `Window` avec `GrilleCategories` (DataGrid, `AutoGenerateColumns=False`, `CanUserAddRows=False`, colonnes « Dossier » et « Extensions »), `BtnAjouter`, `BtnSupprimer`, `BtnEnregistrer`, `BtnFermer`.
  - `Rangeur-UI.ps1 [-Dossier <string>]` : dot-source le script de rangement, définit `Import-Fenetre -Chemin <string>` vers `System.Windows.Window` (XamlReader sur XmlNodeReader), et n'ouvre la fenêtre que hors dot-source. `-Dossier` vaut Téléchargements par défaut.
  - Lignes du tableau des catégories : classe C# `LigneCategorie { string Dossier; string Extensions }` via `Add-Type`, dans une `ObservableCollection`, pour l'édition à deux sens.
  - L'installeur pointe vers `Rangeur-UI.ps1`.

- [ ] **Step 1: Tests qui échouent**

```powershell
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
```

- [ ] **Step 2: Lancer, vérifier l'échec** — Expected: FAIL, `Rangeur-UI.ps1` absent.
- [ ] **Step 3: Implémenter les XAML, `Rangeur-UI.ps1` et l'installeur** — Comportement des boutons : exactement la section « Fenêtre principale » et « Fenêtre des catégories » de la spec. Confirmation d'annulation par `MessageBox` Oui/Non. « Changer… » via `System.Windows.Forms.FolderBrowserDialog`. Chaque gestionnaire d'événement dans un `try/catch` qui affiche l'erreur dans une `MessageBox`.
- [ ] **Step 4: Lancer, vérifier le succès** — Expected: 49 passés, 0 échec.
- [ ] **Step 5: Vérification visuelle** — Lancer `Rangeur-UI.ps1 -Dossier <dossier de test dans le scratchpad>` avec quelques fichiers, vérifier à l'écran : aperçu, Ranger, Annuler, fenêtre des catégories (ajout, enregistrement refusé si invalide). Jamais sur le vrai Téléchargements.
- [ ] **Step 6: Réinstaller le raccourci et commit** — `feat: add WPF window for preview, undo and categories`
