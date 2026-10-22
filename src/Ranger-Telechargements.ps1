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

if ($MyInvocation.InvocationName -ne '.') {
}
