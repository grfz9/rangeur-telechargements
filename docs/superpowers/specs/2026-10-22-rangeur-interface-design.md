# Rangeur de Téléchargements — Interface graphique — Design

Date : 2026-10-22
Statut : design approuvé en conversation, en attente de relecture de la spec
S'appuie sur : `docs/superpowers/specs/2026-10-22-rangeur-telechargements-design.md`

## Objectif

Remplacer le rangement « à l'aveugle » par une fenêtre qui montre ce qui va être rangé avant d'agir, permet d'annuler le dernier rangement, de modifier les catégories sans toucher au code, et de ranger un autre dossier que Téléchargements.

Toutes les règles de la première spec restent valables : on ne supprime et on n'écrase jamais un fichier de l'utilisateur, on ne touche pas aux sous-dossiers, on ignore les téléchargements en cours et les fichiers cachés ou système.

## Approche retenue

Fenêtre WPF pilotée par PowerShell 5.1 (`powershell.exe` est STA par défaut, condition de WPF). Rien à installer. La logique de rangement existante et ses tests sont réutilisés ; la fenêtre ne contient que de l'affichage et des appels aux fonctions testées.

Approches écartées : WinForms (aspect daté), application Python (installation de Python et réécriture complète).

## Fenêtre principale

```
┌ Rangeur de Téléchargements ─────────────────────────────┐
│ Dossier : C:\Users\billa\Downloads        [Changer…]    │
│ ┌ Fichier ───────────────────────┬ Ira dans ──────────┐ │
│ │ facture.pdf                    │ Documents          │ │
│ └────────────────────────────────┴────────────────────┘ │
│ [Ranger] [Annuler le dernier rangement] [Catégories…]   │
│ 12 fichier(s) à ranger                                  │
└─────────────────────────────────────────────────────────┘
```

- **Dossier** : Téléchargements au lancement. « Changer… » ouvre le sélecteur de dossier de Windows. Le choix n'est pas retenu d'un lancement à l'autre.
- **Aperçu** : liste en lecture seule des fichiers qui seront déplacés et de leur catégorie. Elle est recalculée au lancement, après un changement de dossier, après un rangement, après une annulation et après l'enregistrement des catégories.
- **Ranger** : désactivé si l'aperçu est vide. Range le dossier, puis affiche le résumé (`Format-Resume`) dans la barre d'état.
- **Annuler le dernier rangement** : désactivé s'il n'y a rien à annuler dans le dossier affiché. Demande une confirmation, annule, puis affiche le résultat dans la barre d'état.
- **Catégories…** : ouvre la fenêtre des catégories, de façon modale.
- **Barre d'état** : nombre de fichiers à ranger, ou résultat de la dernière action.
- Toute erreur inattendue est affichée dans une boîte de message ; la fenêtre reste ouverte.

## Fenêtre des catégories

- Un tableau éditable à deux colonnes : **Dossier** et **Extensions** (séparées par des virgules, avec ou sans point).
- Boutons **Ajouter une ligne**, **Supprimer la ligne**, **Enregistrer**, **Fermer**.
- `Autres` n'apparaît pas : c'est la catégorie automatique des extensions inconnues.
- À l'enregistrement, les données sont validées. En cas d'erreur, un message clair est affiché et rien n'est écrit :
  - nom de dossier vide, contenant un caractère interdit dans un nom de fichier Windows, ou égal à `Autres` (sans tenir compte de la casse) ;
  - deux lignes avec le même dossier ;
  - une même extension dans deux dossiers.
- Les extensions sont normalisées : espaces et point initial retirés, minuscules, doublons et vides supprimés.
- Renommer ou supprimer une catégorie ne déplace aucun dossier déjà créé sur le disque.

## Catégories dans un fichier

- `src/categories.json`, à côté des scripts : un objet dont chaque clé est un dossier et chaque valeur un tableau d'extensions. L'ordre des clés est l'ordre d'affichage du résumé.
- Si le fichier n'existe pas ou est illisible, la table par défaut (celle de la première spec) est utilisée. Le fichier n'est créé qu'au premier enregistrement depuis la fenêtre.
- Le rangement en un clic (`Ranger-Telechargements.ps1`) utilise aussi ce fichier.

## Aperçu

`Get-PlanRangement` renvoie, pour chaque fichier de la racine qui n'est pas ignoré, son nom et sa catégorie, sans rien modifier. `Invoke-Rangement` parcourt ce même plan : l'aperçu montre exactement les fichiers qui seront traités. Le nom final (avec ` (2)` en cas de conflit) est calculé au moment du déplacement, pas dans l'aperçu.

## Annulation

- Chaque rangement qui déplace au moins un fichier écrit `rangement-dernier.json` à la racine du dossier rangé (UTF-8) : la date et la liste des déplacements `{ De, Vers }` en chemins complets. Il remplace le précédent : une seule annulation possible.
- `rangement-dernier.json` est ignoré par le rangement, comme `rangement.log`.
- L'annulation, pour chaque déplacement :
  - si le fichier n'est plus à l'emplacement `Vers`, il est laissé tel quel et signalé (« introuvable ») ;
  - sinon, il est remis dans le dossier d'origine sous son nom d'origine ; si ce nom est pris, sous `nom (2).ext` (même règle que `Get-CheminLibre`) ;
  - un échec (fichier verrouillé) est signalé et n'arrête pas les autres.
- Chaque fichier remis est journalisé dans `rangement.log` (`restauré | <ancien chemin relatif> -> <nom remis>`), chaque échec aussi (`erreur`).
- Une fois l'annulation terminée, `rangement-dernier.json` est supprimé (c'est un fichier technique du rangeur, pas un fichier de l'utilisateur) pour éviter une double annulation.
- Les dossiers de catégorie vidés restent en place.
- Résumé : `<n> fichier(s) remis en place.` puis, s'il y en a, `<k> fichier(s) non remis, voir rangement.log.` Sans rien à annuler : `Rien à annuler.`

## Lancement

- Nouveau script `src/Rangeur-UI.ps1` et sa description de fenêtre `src/Fenetre.xaml` (et `src/Categories.xaml` pour la fenêtre des catégories).
- L'installeur crée le raccourci **Ranger Téléchargements** vers `Rangeur-UI.ps1` (même ligne de commande qu'avant : `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File`). Il remplace le raccourci existant.
- `Ranger-Telechargements.ps1` reste utilisable seul pour un rangement sans fenêtre.

## Tests

Pester 3.4, sur `TestDrive:` uniquement :

- catégories : lecture d'un fichier valide (ordre conservé), repli sur la table par défaut si absent ou JSON invalide, normalisation des extensions, chaque règle de validation, aller-retour écriture puis lecture ;
- `Get-Categorie` avec une table personnalisée chargée depuis le fichier ;
- aperçu : liste les bons fichiers et catégories, ignore les téléchargements en cours, `rangement.log` et `rangement-dernier.json`, ne déplace rien ;
- rangement : écrit `rangement-dernier.json` avec les bons chemins ; n'en écrit pas si rien n'a bougé ;
- annulation : remet les fichiers, gère un nom repris entre-temps, signale un fichier introuvable, continue après un fichier verrouillé, supprime `rangement-dernier.json`, renvoie « Rien à annuler » sans fichier ;
- fenêtres : les deux XAML se chargent sans erreur et contiennent les contrôles nommés attendus ;
- les 27 tests existants restent verts.

La fenêtre est vérifiée à l'écran sur un dossier de test, jamais sur le vrai dossier Téléchargements sans l'accord de l'utilisateur.

## Hors périmètre

- Cocher ou décocher des fichiers un par un dans l'aperçu.
- Plusieurs niveaux d'annulation.
- Retenir le dernier dossier choisi.
- Renommer ou fusionner des dossiers de catégorie existants sur le disque.
