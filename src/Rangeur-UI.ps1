# Fenêtre du rangeur : aperçu, rangement, annulation du dernier rangement,
# choix du dossier et édition des catégories. Toute la logique vient de
# Ranger-Telechargements.ps1 ; ce script ne fait que l'affichage.

param([string]$Dossier = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))

. "$PSScriptRoot\Ranger-Telechargements.ps1"

Add-Type -AssemblyName PresentationFramework, System.Windows.Forms

# Ligne éditable du tableau des catégories (le DataGrid a besoin de vraies
# propriétés .NET pour l'édition à deux sens).
if (-not ('LigneCategorie' -as [type])) {
    Add-Type -TypeDefinition 'public class LigneCategorie { public string Dossier { get; set; } public string Extensions { get; set; } }'
}

function Import-Fenetre {
    param([string]$Chemin)

    [xml]$xaml = Get-Content -LiteralPath $Chemin -Raw -Encoding UTF8
    return [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
}

function Show-Erreur {
    param([string]$Message)

    [System.Windows.MessageBox]::Show($Message, 'Rangeur de Téléchargements', 'OK', 'Error') | Out-Null
}

# Ouvre la fenêtre des catégories. Renvoie $true si elles ont été enregistrées.
function Show-Categories {
    param([System.Windows.Window]$Proprietaire)

    $fenetre = Import-Fenetre -Chemin (Join-Path $PSScriptRoot 'Categories.xaml')
    $fenetre.Owner = $Proprietaire
    $grille = $fenetre.FindName('GrilleCategories')

    $lignes = New-Object 'System.Collections.ObjectModel.ObservableCollection[LigneCategorie]'
    foreach ($nom in $script:Categories.Keys) {
        $ligne = New-Object LigneCategorie
        $ligne.Dossier = $nom
        $ligne.Extensions = $script:Categories[$nom] -join ', '
        $lignes.Add($ligne)
    }
    $grille.ItemsSource = $lignes

    # La collection ne peut pas changer pendant qu'une cellule est en cours
    # d'édition : on valide d'abord la saisie.
    $fenetre.FindName('BtnAjouter').Add_Click({
        try {
            $grille.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
            $ligne = New-Object LigneCategorie
            $lignes.Add($ligne)
            $grille.SelectedItem = $ligne
            $grille.ScrollIntoView($ligne)
        }
        catch { Show-Erreur $_.Exception.Message }
    })
    $fenetre.FindName('BtnSupprimer').Add_Click({
        try {
            $grille.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
            if ($grille.SelectedItem -is [LigneCategorie]) { $lignes.Remove($grille.SelectedItem) | Out-Null }
        }
        catch { Show-Erreur $_.Exception.Message }
    })
    $fenetre.FindName('BtnEnregistrer').Add_Click({
        $grille.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
        try {
            $table = ConvertTo-TableCategories -Lignes @($lignes)
            Save-Categories -Chemin $CheminCategories -Table $table
            $script:Categories = $table
            $fenetre.DialogResult = $true
        }
        catch {
            [System.Windows.MessageBox]::Show($_.Exception.Message, 'Catégories', 'OK', 'Warning') | Out-Null
        }
    })
    $fenetre.FindName('BtnFermer').Add_Click({ $fenetre.Close() })

    return [bool]$fenetre.ShowDialog()
}

function Show-Rangeur {
    param([string]$Dossier)

    $fenetre = Import-Fenetre -Chemin (Join-Path $PSScriptRoot 'Fenetre.xaml')
    $c = @{}
    foreach ($nom in 'TxtDossier', 'BtnChanger', 'ListeApercu', 'BtnRanger', 'BtnAnnuler', 'BtnCategories', 'TxtEtat') {
        $c[$nom] = $fenetre.FindName($nom)
    }
    # Table partagée avec les gestionnaires d'événements, qui ne peuvent pas
    # réaffecter les variables locales de cette fonction.
    $etat = @{ Dossier = $Dossier }

    # Recalcule l'aperçu et l'état des boutons. Message remplace le texte
    # par défaut de la barre d'état.
    $actualiser = {
        param([string]$Message)

        $c.TxtDossier.Text = $etat.Dossier
        $c.ListeApercu.ItemsSource = $null
        $c.BtnRanger.IsEnabled = $false
        $c.BtnAnnuler.IsEnabled = $false
        try {
            $plan = @(Get-PlanRangement -Source $etat.Dossier)
            $c.ListeApercu.ItemsSource = $plan
            $c.BtnRanger.IsEnabled = $plan.Count -gt 0
            $c.BtnAnnuler.IsEnabled = Test-AnnulationPossible -Source $etat.Dossier
            if ($Message) { $c.TxtEtat.Text = $Message }
            else { $c.TxtEtat.Text = "$($plan.Count) fichier(s) à ranger" }
        }
        catch {
            $c.TxtEtat.Text = "Dossier illisible : $($_.Exception.Message)"
        }
    }

    $c.BtnChanger.Add_Click({
        try {
            $choix = New-Object System.Windows.Forms.FolderBrowserDialog
            $choix.Description = 'Dossier à ranger'
            $choix.SelectedPath = $etat.Dossier
            if ($choix.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $etat.Dossier = $choix.SelectedPath
                & $actualiser
            }
        }
        catch { Show-Erreur $_.Exception.Message }
    })

    $c.BtnRanger.Add_Click({
        try {
            $resultat = Invoke-Rangement -Source $etat.Dossier
            & $actualiser (Format-Resume -Resultat $resultat)
        }
        catch { Show-Erreur $_.Exception.Message }
    })

    $c.BtnAnnuler.Add_Click({
        try {
            $reponse = [System.Windows.MessageBox]::Show(
                'Remettre les fichiers du dernier rangement à leur place ?',
                'Annuler le dernier rangement', 'YesNo', 'Question')
            if ($reponse -eq [System.Windows.MessageBoxResult]::Yes) {
                $resultat = Undo-Rangement -Source $etat.Dossier
                & $actualiser (Format-ResumeAnnulation -Resultat $resultat)
            }
        }
        catch { Show-Erreur $_.Exception.Message }
    })

    $c.BtnCategories.Add_Click({
        try {
            if (Show-Categories -Proprietaire $fenetre) { & $actualiser 'Catégories enregistrées.' }
        }
        catch { Show-Erreur $_.Exception.Message }
    })

    & $actualiser
    $fenetre.ShowDialog() | Out-Null
}

if ($MyInvocation.InvocationName -ne '.') {
    Show-Rangeur -Dossier $Dossier
}
