# Mon Agent — assistant IA personnel pour iPhone

App SwiftUI à trois onglets :

- **Agent** : un assistant propulsé par Claude (Anthropic) qui agit pour toi.
  - Agenda : consulte tes événements et en crée (avec ta validation).
  - Rappels : consulte et crée des rappels (avec ta validation).
  - E-mails : rédige un e-mail et ouvre la fenêtre d'envoi ; c'est toi qui envoies.
  - Contacts : retrouve un numéro ou une adresse e-mail.
  - Lieux : cherche restaurants, commerces, adresses ; ouvre l'itinéraire ; lance un appel.
  - Recherche web : informations à jour (prix, horaires, actualités).
  - muse.ai : ouvre l'onglet muse.ai sur la page demandée.
- **muse.ai** : le site https://muse.ai dans l'app (session persistante, swipe arrière, tirer pour rafraîchir).
- **Réglages** : clé API Anthropic (gardée dans le trousseau), déconnexion de muse.ai.

## Installation (Mac + Xcode requis)
```bash
brew install xcodegen
```
```bash
xcodegen generate && open MuseApp.xcodeproj
```
Dans Xcode : cible MuseApp → Signing & Capabilities → choisis ton Team, branche l'iPhone, ⌘R.
Requiert iOS 17 ou plus.

Au premier lancement : onglet Réglages → colle ta clé API (https://console.anthropic.com/settings/keys).

## Limites
- Les requêtes à Claude sont facturées sur ton compte Anthropic.
- Pas d'achats ni de réservations en ligne : l'agent te donne les liens et numéros.
- Muse de Meta n'a pas d'API publique pour piloter son agent : l'onglet muse.ai affiche le site tel quel.
- L'e-mail utilise l'app Mail de l'iPhone ; sans compte Mail configuré, il ouvre ta messagerie par défaut.

## Fichiers
| Fichier | Rôle |
|---|---|
| `MuseApp/MuseApp.swift` | Point d'entrée, barre d'onglets |
| `MuseApp/ChatView.swift` | Écran de conversation, cartes de validation |
| `MuseApp/AgentViewModel.swift` | Boucle de l'agent, consignes, validation des actions |
| `MuseApp/AgentTools.swift` | Outils : agenda, rappels, e-mail, contacts, lieux, muse.ai |
| `MuseApp/ClaudeClient.swift` | Appel de l'API Messages d'Anthropic |
| `MuseApp/MuseTab.swift`, `WebView.swift` | Onglet muse.ai |
| `MuseApp/SettingsView.swift`, `Keychain.swift` | Réglages et stockage de la clé |
