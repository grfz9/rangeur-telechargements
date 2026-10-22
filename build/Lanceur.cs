// Lanceur du rangeur : copie les scripts embarqués dans
// %LOCALAPPDATA%\Rangeur puis ouvre la fenêtre via PowerShell, sans console.
// Le fichier categories.json de l'utilisateur n'est pas embarqué, donc
// jamais écrasé par une mise à jour.
//
// Options (utilisées par les tests) :
//   --sans-lancer                    copie les fichiers sans ouvrir la fenêtre
//   --dossier-installation <chemin>  remplace %LOCALAPPDATA%\Rangeur

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

static class Lanceur
{
    [STAThread]
    static int Main(string[] args)
    {
        string dossier = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Rangeur");
        bool sansLancer = false;

        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--sans-lancer") sansLancer = true;
            else if (args[i] == "--dossier-installation" && i + 1 < args.Length) dossier = args[++i];
        }

        try
        {
            Directory.CreateDirectory(dossier);
            Assembly assemblage = Assembly.GetExecutingAssembly();
            foreach (string nom in assemblage.GetManifestResourceNames())
            {
                using (Stream source = assemblage.GetManifestResourceStream(nom))
                using (FileStream cible = File.Create(Path.Combine(dossier, nom)))
                {
                    source.CopyTo(cible);
                }
            }

            if (sansLancer) return 0;

            string script = Path.Combine(dossier, "Rangeur-UI.ps1");
            ProcessStartInfo demarrage = new ProcessStartInfo(
                "powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
            demarrage.UseShellExecute = false;
            demarrage.CreateNoWindow = true;
            Process.Start(demarrage);
            return 0;
        }
        catch (Exception erreur)
        {
            MessageBox.Show("Impossible de démarrer le rangeur : " + erreur.Message,
                "Rangeur de Téléchargements", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
