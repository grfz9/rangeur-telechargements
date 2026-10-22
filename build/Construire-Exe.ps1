# Compile Rangeur.exe avec le compilateur C# fourni par Windows
# (.NET Framework 4), en y embarquant les scripts et les fenêtres de src.

param([string]$Sortie = (Join-Path $PSScriptRoot '..\dist\Rangeur.exe'))

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "Compilateur C# introuvable : $csc" }

$src = Join-Path $PSScriptRoot '..\src'
$ressources = foreach ($nom in 'Ranger-Telechargements.ps1', 'Rangeur-UI.ps1', 'Fenetre.xaml', 'Categories.xaml') {
    "/resource:$(Join-Path $src $nom),$nom"
}

$dossierSortie = Split-Path -Parent $Sortie
if (-not (Test-Path -LiteralPath $dossierSortie)) { New-Item -ItemType Directory -Path $dossierSortie | Out-Null }

& $csc /nologo /target:winexe /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll `
    "/out:$Sortie" @ressources (Join-Path $PSScriptRoot 'Lanceur.cs')
if ($LASTEXITCODE -ne 0) { throw "La compilation a échoué (code $LASTEXITCODE)." }

Write-Output (Convert-Path -LiteralPath $Sortie)
