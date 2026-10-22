# Range les fichiers de la racine du dossier Téléchargements dans des
# sous-dossiers par type. Ne supprime et n'écrase jamais rien.

# Table par défaut, utilisée tant que categories.json n'existe pas.
# Dossier de destination -> extensions (sans point, en minuscules).
# Toute extension absente de la table va dans 'Autres'.
$CategoriesParDefaut = [ordered]@{
    'Images'      = @('jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'heic', 'ico', 'tiff')
    'Vidéos'      = @('mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'flv', 'm4v')
    'Musique'     = @('mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma')
    'Documents'   = @('pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'txt', 'rtf', 'csv', 'md', 'epub')
    'Archives'    = @('zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso')
    'Installeurs' = @('exe', 'msi', 'msix', 'appx', 'bat', 'cmd')
    'Code'        = @('py', 'js', 'ts', 'html', 'css', 'json', 'xml', 'ps1', 'java', 'c', 'cpp', 'cs', 'sql', 'yml', 'yaml')
}

# Extensions des téléchargements encore en cours : ces fichiers restent en place.
$ExtensionsEnCours = @('crdownload', 'part', 'tmp', 'partial', 'download')

$NomJournal = 'rangement.log'
# Liste des déplacements du dernier rangement, lue par Undo-Rangement.
$NomAnnulation = 'rangement-dernier.json'

function Copy-Categories {
    param([System.Collections.IDictionary]$Table)

    $copie = [ordered]@{}
    foreach ($nom in $Table.Keys) { $copie[$nom] = @($Table[$nom]) }
    return $copie
}

# Construit une table de catégories à partir de lignes { Dossier; Extensions },
# où Extensions est une liste séparée par des virgules. Normalise les
# extensions et lève une exception si les données sont invalides.
function ConvertTo-TableCategories {
    param([object[]]$Lignes)

    $table = [ordered]@{}
    $dossiers = @()
    $proprietaires = @{}
    $interdits = [IO.Path]::GetInvalidFileNameChars()

    foreach ($ligne in $Lignes) {
        $nom = "$($ligne.Dossier)".Trim()
        if (-not $nom) { throw 'Un nom de dossier est vide.' }
        if ($nom.IndexOfAny($interdits) -ge 0) { throw "Le nom de dossier « $nom » contient un caractère interdit." }
        if ($nom -eq 'Autres') { throw '« Autres » est réservé aux extensions inconnues.' }
        if ($dossiers -contains $nom) { throw "Le dossier « $nom » apparaît deux fois." }
        $dossiers += $nom

        $extensions = @()
        foreach ($brut in "$($ligne.Extensions)".Split(',')) {
            $ext = $brut.Trim().TrimStart('.').ToLowerInvariant()
            if (-not $ext -or $extensions -contains $ext) { continue }
            if ($proprietaires.ContainsKey($ext)) {
                throw "L'extension « $ext » est à la fois dans « $($proprietaires[$ext]) » et « $nom »."
            }
            $proprietaires[$ext] = $nom
            $extensions += $ext
        }
        $table[$nom] = $extensions
    }
    return $table
}

# Lit categories.json. Renvoie une copie de la table par défaut si le
# fichier manque, n'est pas du JSON ou ne respecte pas les règles.
function Read-Categories {
    param([string]$Chemin)

    try {
        if (-not (Test-Path -LiteralPath $Chemin -PathType Leaf)) { throw 'absent' }
        $json = Get-Content -LiteralPath $Chemin -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $lignes = foreach ($p in $json.PSObject.Properties) {
            [pscustomobject]@{ Dossier = $p.Name; Extensions = (@($p.Value) -join ',') }
        }
        return ConvertTo-TableCategories -Lignes @($lignes)
    }
    catch {
        return Copy-Categories $CategoriesParDefaut
    }
}

function Save-Categories {
    param([string]$Chemin, [System.Collections.IDictionary]$Table)

    $objet = [ordered]@{}
    foreach ($nom in $Table.Keys) { $objet[$nom] = @($Table[$nom]) }
    $objet | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Chemin -Encoding UTF8 -ErrorAction Stop
}

$CheminCategories = Join-Path $PSScriptRoot 'categories.json'
$Categories = Read-Categories -Chemin $CheminCategories

function Get-Categorie {
    param([string]$Extension, [System.Collections.IDictionary]$Table = $Categories)

    $ext = $Extension.TrimStart('.').ToLowerInvariant()
    if ($ext) {
        foreach ($nom in $Table.Keys) {
            if ($Table[$nom] -contains $ext) { return $nom }
        }
    }
    return 'Autres'
}

function Test-FichierAIgnorer {
    param([System.IO.FileInfo]$Fichier)

    if ($Fichier.Name -eq $NomJournal -or $Fichier.Name -eq $NomAnnulation) { return $true }
    if ($Fichier.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) { return $true }
    if ($ExtensionsEnCours -contains $Fichier.Extension.TrimStart('.').ToLowerInvariant()) { return $true }

    # Firefox crée un fichier vide au nom final à côté du .part pendant le
    # téléchargement : il ne doit pas être rangé avant la fin.
    foreach ($ext in $ExtensionsEnCours) {
        if (Test-Path -LiteralPath "$($Fichier.FullName).$ext") { return $true }
    }
    return $false
}

# Renvoie Dossier\Nom s'il est libre, sinon Dossier\base (n).ext avec le plus
# petit n >= 2 libre. Ne crée aucun fichier.
function Get-CheminLibre {
    param([string]$Dossier, [string]$Nom)

    $chemin = Join-Path $Dossier $Nom
    if (-not (Test-Path -LiteralPath $chemin)) { return $chemin }

    $base = [IO.Path]::GetFileNameWithoutExtension($Nom)
    $ext = [IO.Path]::GetExtension($Nom)
    $n = 2
    do {
        $chemin = Join-Path $Dossier "$base ($n)$ext"
        $n++
    } while (Test-Path -LiteralPath $chemin)
    return $chemin
}

# Liste les fichiers de la racine de Source qui seraient rangés, avec leur
# catégorie, sans rien déplacer. Invoke-Rangement suit exactement ce plan.
function Get-PlanRangement {
    param([string]$Source)

    $racine = Convert-Path -LiteralPath $Source -ErrorAction Stop
    $plan = foreach ($fichier in Get-ChildItem -LiteralPath $racine -File -Force) {
        if (Test-FichierAIgnorer -Fichier $fichier) { continue }
        [pscustomobject]@{
            Nom       = $fichier.Name
            Chemin    = $fichier.FullName
            Categorie = Get-Categorie -Extension $fichier.Extension
        }
    }
    return @($plan)
}

# Déplace chaque fichier de la racine de Source dans son dossier de catégorie
# et journalise chaque action. Les sous-dossiers ne sont pas parcourus.
# Renvoie le nombre de fichiers rangés par catégorie et la liste des erreurs.
function Invoke-Rangement {
    param([string]$Source, [string]$Journal)

    $racine = Convert-Path -LiteralPath $Source -ErrorAction Stop
    if (-not $Journal) { $Journal = Join-Path $racine $NomJournal }

    $comptes = @{}
    $erreurs = New-Object System.Collections.Generic.List[string]
    $deplacements = New-Object System.Collections.Generic.List[object]

    foreach ($entree in Get-PlanRangement -Source $racine) {
        $categorie = $entree.Categorie
        $horodatage = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        try {
            $dossier = Join-Path $racine $categorie
            if (-not (Test-Path -LiteralPath $dossier -PathType Container)) {
                New-Item -ItemType Directory -Path $dossier -ErrorAction Stop | Out-Null
            }
            $destination = Get-CheminLibre -Dossier $dossier -Nom $entree.Nom
            Move-Item -LiteralPath $entree.Chemin -Destination $destination -ErrorAction Stop

            $comptes[$categorie] = 1 + [int]$comptes[$categorie]
            $deplacements.Add([pscustomobject]@{ De = $entree.Chemin; Vers = $destination })
            $nomFinal = Split-Path -Leaf $destination
            Add-Content -LiteralPath $Journal -Encoding UTF8 -Value "$horodatage | déplacé | $($entree.Nom) -> $categorie\$nomFinal"
        }
        catch {
            $erreurs.Add("$($entree.Nom) : $($_.Exception.Message)")
            Add-Content -LiteralPath $Journal -Encoding UTF8 -Value "$horodatage | erreur | $($entree.Nom) | $($_.Exception.Message)"
        }
    }

    # Un rangement qui n'a rien déplacé garde l'annulation précédente.
    if ($deplacements.Count -gt 0) {
        $annulation = [pscustomobject]@{
            Date         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Deplacements = $deplacements.ToArray()
        }
        $annulation | ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath (Join-Path $racine $NomAnnulation) -Encoding UTF8
    }

    return [pscustomobject]@{ Comptes = $comptes; Erreurs = $erreurs.ToArray() }
}

# Construit le texte affiché à l'utilisateur à partir du résultat de
# Invoke-Rangement. Les catégories suivent l'ordre de la table.
function Format-Resume {
    param([pscustomobject]$Resultat)

    $erreurs = @($Resultat.Erreurs).Count
    $total = 0
    $parties = @()
    foreach ($nom in @($Categories.Keys) + 'Autres') {
        $n = [int]$Resultat.Comptes[$nom]
        if ($n -gt 0) {
            $total += $n
            $parties += "$n $nom"
        }
    }

    if ($total -eq 0 -and $erreurs -eq 0) {
        return 'Rien à ranger : le dossier Téléchargements est déjà propre.'
    }

    if ($total -eq 0) {
        $texte = '0 fichier(s) rangé(s).'
    }
    else {
        $texte = "$total fichier(s) rangé(s) : " + ($parties -join ', ')
    }
    if ($erreurs -gt 0) {
        $texte += "`r`n$erreurs fichier(s) non déplacé(s), voir $NomJournal."
    }
    return $texte
}

function Test-AnnulationPossible {
    param([string]$Source)

    return Test-Path -LiteralPath (Join-Path $Source $NomAnnulation) -PathType Leaf
}

# Remet à leur place les fichiers du dernier rangement de Source, d'après
# rangement-dernier.json, puis supprime ce fichier technique. Un fichier qui
# n'est plus où le rangement l'avait mis est laissé tel quel et signalé.
function Undo-Rangement {
    param([string]$Source)

    $racine = Convert-Path -LiteralPath $Source -ErrorAction Stop
    $cheminAnnulation = Join-Path $racine $NomAnnulation
    $journal = Join-Path $racine $NomJournal
    $rien = [pscustomobject]@{ RienAAnnuler = $true; Restaures = 0; Erreurs = @() }

    if (-not (Test-Path -LiteralPath $cheminAnnulation -PathType Leaf)) { return $rien }
    try {
        $annulation = Get-Content -LiteralPath $cheminAnnulation -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $rien
    }

    $restaures = 0
    $erreurs = New-Object System.Collections.Generic.List[string]

    foreach ($deplacement in @($annulation.Deplacements)) {
        $horodatage = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $nom = Split-Path -Leaf $deplacement.De
        try {
            if (-not (Test-Path -LiteralPath $deplacement.Vers -PathType Leaf)) {
                throw "introuvable à l'emplacement $($deplacement.Vers)"
            }
            $destination = Get-CheminLibre -Dossier (Split-Path -Parent $deplacement.De) -Nom $nom
            Move-Item -LiteralPath $deplacement.Vers -Destination $destination -ErrorAction Stop

            $restaures++
            $relatif = $deplacement.Vers.Substring($racine.Length).TrimStart('\')
            Add-Content -LiteralPath $journal -Encoding UTF8 -Value "$horodatage | restauré | $relatif -> $(Split-Path -Leaf $destination)"
        }
        catch {
            $erreurs.Add("$nom : $($_.Exception.Message)")
            Add-Content -LiteralPath $journal -Encoding UTF8 -Value "$horodatage | erreur | $nom | $($_.Exception.Message)"
        }
    }

    Remove-Item -LiteralPath $cheminAnnulation
    return [pscustomobject]@{ RienAAnnuler = $false; Restaures = $restaures; Erreurs = $erreurs.ToArray() }
}

function Format-ResumeAnnulation {
    param([pscustomobject]$Resultat)

    if ($Resultat.RienAAnnuler) { return 'Rien à annuler.' }

    $texte = "$($Resultat.Restaures) fichier(s) remis en place."
    $erreurs = @($Resultat.Erreurs).Count
    if ($erreurs -gt 0) {
        $texte += "`r`n$erreurs fichier(s) non remis, voir $NomJournal."
    }
    return $texte
}

# Range Source et renvoie le message à afficher. Le script tourne dans une
# fenêtre cachée : toute erreur fatale doit finir dans ce message.
function Get-MessageFinal {
    param([string]$Source)

    try {
        return Format-Resume -Resultat (Invoke-Rangement -Source $Source)
    }
    catch {
        return "Le rangement a échoué : $($_.Exception.Message)"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $telechargements = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    $message = Get-MessageFinal -Source $telechargements

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($message, 'Rangeur de Téléchargements') | Out-Null
}
