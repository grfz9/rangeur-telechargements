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
    return $ExtensionsEnCours -contains $Fichier.Extension.TrimStart('.').ToLowerInvariant()
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

    $racine = Convert-Path -LiteralPath $Source
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

if ($MyInvocation.InvocationName -ne '.') {
}
