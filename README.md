# MuseApp — le dashboard muse.ai dans une app iOS

App SwiftUI minimale qui affiche https://muse.ai/dashboard dans une WKWebView.

## Fonctionnalités
- Session persistante (tu restes connecté)
- Swipe gauche/droite pour page précédente/suivante, tirer pour rafraîchir
- Barre de progression, message d'erreur avec « Réessayer »
- Upload de vidéos (caméra / photothèque), lecture vidéo inline
- Liens `target="_blank"` ouverts dans l'app, `mailto:`/`tel:` ouverts à l'extérieur

## Générer le projet Xcode (Mac requis)
```bash
brew install xcodegen
```
```bash
cd MuseApp && xcodegen generate && open MuseApp.xcodeproj
```
Dans Xcode : cible MuseApp → Signing & Capabilities → choisis ton Team (un Apple ID gratuit suffit),
branche ton iPhone, puis ⌘R.

### Sans XcodeGen
Xcode → New Project → iOS App (SwiftUI), nom « MuseApp », puis remplace les fichiers
générés par les 3 fichiers de `MuseApp/`. Ajoute les clés caméra / micro / photothèque
dans l'onglet Info de la cible.

## Changer l'adresse de départ
`MuseApp/ContentView.swift`, constante `startURL`.
