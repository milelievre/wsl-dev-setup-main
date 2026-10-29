# Captures d'écran de la cinématique

Ce dossier contient les captures d'écran utilisées dans la section **Aperçu de l'exécution** du [README principal](../../README.md).

> `docs/` regroupe la documentation projet. Le dossier `images/` (à la racine) est réservé aux **assets Docker** (exemples de `Dockerfile`, `docker-compose.yml`) et ne doit pas contenir de captures.

## Fichiers attendus

| Fichier                  | Contenu                                                                             | Taille recommandée |
|--------------------------|-------------------------------------------------------------------------------------|--------------------|
| `vscode-remote-wsl.png`  | VS Code fraîchement lancé, connecté à l'instance WSL, terminal ouvert dans `$HOME`. | 1600 × 1000 px     |

## Comment produire `vscode-remote-wsl.png`

1. Terminer une installation propre via `install.ps1` sur une VM Windows.
2. Attendre que VS Code s'ouvre automatiquement en Remote-WSL.
3. Ouvrir un terminal intégré (`Ctrl+ù`) puis lancer :

   ```bash
   whoami && docker --version && docker compose version
   ```

4. Vérifier que le badge en bas à gauche affiche bien `WSL: <nom-instance>`.
5. Capturer la fenêtre entière (Win + Shift + S) et exporter en PNG dans ce dossier.

## Conventions

- **Format** : PNG optimisé (`oxipng` ou `pngquant --quality=80-95`).
- **Thème VS Code** : sombre par défaut (Dark Modern) pour cohérence visuelle avec les blocs terminal.
- **Anonymisation** : masquer les tokens, chemins réseau internes, noms d'entreprise éventuels.
