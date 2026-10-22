# Rangeur de Téléchargements — Design

Date : 2026-10-22
Statut : approuvé en conversation, en attente de relecture de la spec

## Objectif

Vider la racine du dossier `C:\Users\billa\Downloads` en un double-clic, en rangeant chaque fichier dans un sous-dossier selon son type, sans jamais perdre ni supprimer de fichier.

## Utilisateur et contexte

- Un seul utilisateur, sur Windows 11.
- Lancement manuel par double-clic sur un raccourci du Bureau. Pas de tâche planifiée, pas de surveillance en continu.
- Aucune suppression : le script range, il ne nettoie pas.

## Critères de réussite

1. Après un lancement, la racine de Téléchargements ne contient plus que des sous-dossiers (et les téléchargements encore en cours).
2. Aucun fichier n'est écrasé ni supprimé.
3. L'utilisateur voit un résumé de ce qui a été rangé.
4. Chaque déplacement est tracé dans un journal.

## Approche retenue

Script PowerShell (`Ranger-Telechargements.ps1`) lancé par un raccourci `.lnk` sur le Bureau. PowerShell est natif sur Windows : rien à installer.

Approches écartées :
- Script Python : demande d'installer et maintenir Python.
- Application avec interface graphique : beaucoup plus de travail pour le même résultat.

## Catégories

Table de correspondance définie en tête du script, modifiable à la main. La comparaison des extensions ignore la casse.

| Dossier       | Extensions |
|---------------|------------|
| `Images`      | jpg, jpeg, png, gif, bmp, webp, svg, heic, ico, tiff |
| `Vidéos`      | mp4, mkv, avi, mov, wmv, webm, flv, m4v |
| `Musique`     | mp3, wav, flac, aac, ogg, m4a, wma |
| `Documents`   | pdf, doc, docx, xls, xlsx, ppt, pptx, odt, ods, odp, txt, rtf, csv, md, epub |
| `Archives`    | zip, rar, 7z, tar, gz, bz2, xz, iso |
| `Installeurs` | exe, msi, msix, appx, bat, cmd |
| `Code`        | py, js, ts, html, css, json, xml, ps1, java, c, cpp, cs, sql, yml, yaml |
| `Autres`      | toute extension absente de la table, et les fichiers sans extension |

## Règles

1. Seuls les fichiers situés directement à la racine de Téléchargements sont traités. Les sous-dossiers et leur contenu ne sont jamais touchés.
2. Les téléchargements en cours sont ignorés : extensions `crdownload`, `part`, `tmp`, `partial`, `download`.
3. Les fichiers cachés ou système (par exemple `desktop.ini`) sont ignorés.
4. Le dossier de destination est créé s'il n'existe pas.
5. Si un fichier du même nom existe déjà dans la destination, le fichier déplacé est renommé `nom (2).ext`, puis `nom (3).ext`, et ainsi de suite. Aucun écrasement.
6. Si un déplacement échoue (fichier ouvert par une autre application, droits insuffisants), le fichier reste en place, l'erreur est journalisée et le script continue avec les fichiers suivants.

## Composants

Le script est découpé en fonctions testables séparément :

- `Get-Categorie -Extension <string>` : renvoie le nom du dossier de destination pour une extension.
- `Test-FichierAIgnorer -Fichier <FileInfo>` : renvoie vrai pour un téléchargement en cours ou un fichier caché/système.
- `Get-CheminLibre -Dossier <string> -Nom <string>` : renvoie un chemin de destination qui n'existe pas encore, en ajoutant ` (n)` si besoin.
- `Invoke-Rangement -Source <string> -Journal <string>` : parcourt la racine de `Source`, déplace les fichiers, écrit le journal, et renvoie le nombre de fichiers rangés par catégorie et la liste des erreurs.
- Bloc principal : appelle `Invoke-Rangement` sur le vrai dossier Téléchargements, puis affiche le résumé.

Le paramètre `-Source` permet aux tests de travailler sur un dossier temporaire. Le dossier par défaut est `[Environment]::GetFolderPath('UserProfile')\Downloads`.

## Résumé et journal

- Résumé : une boîte de dialogue Windows (`System.Windows.Forms.MessageBox`) affiche par exemple « 42 fichiers rangés : 12 Images, 8 Documents… ». S'il y a eu des erreurs, leur nombre est indiqué. Si rien n'est à ranger, le message le dit.
- Journal : `Downloads\rangement.log`, en ajout. Une ligne par action, au format `2026-10-22 18:30:05 | déplacé | facture.pdf -> Documents\facture.pdf`, ou `erreur | <fichier> | <message>`. Le fichier `rangement.log` lui-même n'est jamais déplacé.

## Installation

- Le script est placé dans un dossier choisi par l'utilisateur.
- Un raccourci sur le Bureau lance `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<chemin>\Ranger-Telechargements.ps1"`. L'option `-ExecutionPolicy Bypass` s'applique à ce seul lancement et ne modifie pas la configuration de sécurité de Windows.
- Un petit script `Installer-Raccourci.ps1` crée ce raccourci.

## Tests

Tests Pester sur un dossier temporaire (`TestDrive:`), jamais sur le vrai dossier Téléchargements :

- une extension connue va dans le bon dossier, quelle que soit la casse ;
- une extension inconnue et un fichier sans extension vont dans `Autres` ;
- un `.crdownload` reste à la racine ;
- un sous-dossier existant et son contenu ne bougent pas ;
- un conflit de nom produit `nom (2).ext` sans écraser l'original ;
- `rangement.log` n'est pas déplacé et contient une ligne par fichier rangé ;
- un fichier verrouillé reste en place et apparaît dans les erreurs, sans arrêter le rangement.

## Hors périmètre

- Suppression ou mise à la Corbeille de fichiers.
- Lancement automatique ou surveillance en continu.
- Annulation automatique d'un rangement (le journal permet de retrouver les fichiers à la main).
- Rangement par date.
