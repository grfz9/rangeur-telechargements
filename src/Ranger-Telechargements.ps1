# Range les fichiers de la racine du dossier Téléchargements dans des
# sous-dossiers par type. Ne supprime et n'écrase jamais rien.

# Dossier de destination -> extensions (sans point, en minuscules).
# Toute extension absente de cette table va dans 'Autres'.
$Categories = [ordered]@{
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

function Get-Categorie {
    param([string]$Extension)

    $ext = $Extension.TrimStart('.').ToLowerInvariant()
    if ($ext) {
        foreach ($nom in $Categories.Keys) {
            if ($Categories[$nom] -contains $ext) { return $nom }
        }
    }
    return 'Autres'
}

function Test-FichierAIgnorer {
    param([System.IO.FileInfo]$Fichier)

    if ($Fichier.Name -eq $NomJournal) { return $true }
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

# Déplace chaque fichier de la racine de Source dans son dossier de catégorie
# et journalise chaque action. Les sous-dossiers ne sont pas parcourus.
# Renvoie le nombre de fichiers rangés par catégorie et la liste des erreurs.
function Invoke-Rangement {
    param([string]$Source, [string]$Journal)

    $racine = Convert-Path -LiteralPath $Source -ErrorAction Stop
    if (-not $Journal) { $Journal = Join-Path $racine $NomJournal }

    $comptes = @{}
    $erreurs = New-Object System.Collections.Generic.List[string]

    foreach ($fichier in Get-ChildItem -LiteralPath $racine -File -Force) {
        if (Test-FichierAIgnorer -Fichier $fichier) { continue }

        $categorie = Get-Categorie -Extension $fichier.Extension
        $horodatage = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        try {
            $dossier = Join-Path $racine $categorie
            if (-not (Test-Path -LiteralPath $dossier -PathType Container)) {
                New-Item -ItemType Directory -Path $dossier -ErrorAction Stop | Out-Null
            }
            $destination = Get-CheminLibre -Dossier $dossier -Nom $fichier.Name
            Move-Item -LiteralPath $fichier.FullName -Destination $destination -ErrorAction Stop

            $comptes[$categorie] = 1 + [int]$comptes[$categorie]
            $nomFinal = Split-Path -Leaf $destination
            Add-Content -LiteralPath $Journal -Encoding UTF8 -Value "$horodatage | déplacé | $($fichier.Name) -> $categorie\$nomFinal"
        }
        catch {
            $erreurs.Add("$($fichier.Name) : $($_.Exception.Message)")
            Add-Content -LiteralPath $Journal -Encoding UTF8 -Value "$horodatage | erreur | $($fichier.Name) | $($_.Exception.Message)"
        }
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
