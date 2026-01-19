# 🔄 Système de Mise à Jour UploadDND

Ce document explique comment fonctionne le système de mise à jour automatique d'UploadDND.

## 📋 Vue d'ensemble

UploadDND intègre un système intelligent de détection et de mise à jour qui :
- ✅ Détecte automatiquement les nouvelles versions au démarrage de Rails
- ✅ Compare les fichiers installés avec ceux de la gem
- ✅ Propose une mise à jour sélective des fichiers obsolètes
- ✅ **Préserve vos modèles et configurations personnalisées**

## 🎯 Fichiers trackés vs préservés

### Fichiers mis à jour automatiquement (SAFE)

Ces fichiers sont **copiés depuis la gem** et peuvent être mis à jour sans risque :

| Fichier | Description |
|---------|-------------|
| `app/javascript/controllers/upload_d_n_d/uploads_controller.js` | Controller Stimulus principal |
| `app/javascript/controllers/upload_d_n_d/preview_controller.js` | Controller Stimulus preview |
| `app/assets/stylesheets/upload_d_n_d.css` | Styles CSS (modales, dropzone) |
| `app/components/upload_d_n_d/upload_component.rb` | ViewComponent Ruby |
| `app/components/upload_d_n_d/upload_component.html.erb` | Template ViewComponent |

### Fichiers préservés (NEVER TOUCHED)

Ces fichiers sont **personnalisables** et ne seront **jamais écrasés** :

- `app/models/concerns/upload_d_n_d/uploadable.rb` - Concern modèle
- `app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb` - Concern controller
- `app/helpers/upload_d_n_d/upload_helper.rb` - Helpers
- `config/initializers/upload_d_n_d.rb` - Configuration
- `app/models/**/*.rb` - Tous vos modèles

## 🚀 Utilisation

### Installation initiale

Lors de l'installation, un fichier `.upload_d_n_d_version` est créé à la racine de votre app :

```bash
rails g upload_d_n_d:install
```

Ce fichier contient la version installée (ex: `0.2.0`) et permet le tracking automatique.

### Détection automatique

Au démarrage de Rails en **développement**, si une nouvelle version est disponible, vous verrez :

```
╔════════════════════════════════════════════════════════════════╗
║  📦 UploadDND - Mise à jour disponible                         ║
╠════════════════════════════════════════════════════════════════╣
║  Version installée : 0.1.0                                     ║
║  Version disponible: 0.2.0                                     ║
║                                                                ║
║  Fichiers obsolètes: 3                                         ║
║  • uploads_controller.js                                       ║
║  • application.css                                             ║
║  • upload_component.rb                                         ║
║                                                                ║
║  Pour mettre à jour (recommandé):                             ║
║  $ rails upload_d_n_d:update                                  ║
║                                                                ║
║  ⚠️  Vos modèles et configurations seront préservés            ║
╚════════════════════════════════════════════════════════════════╝
```

### Mise à jour

```bash
# Mise à jour interactive (recommandé)
rails g upload_d_n_d:update

# Mise à jour automatique sans confirmation
rails g upload_d_n_d:update --force

# Simulation (dry-run) pour voir ce qui serait fait
rails g upload_d_n_d:update --dry-run
```

### Exemple de sortie

```bash
$ rails g upload_d_n_d:update

📦 UploadDND Update
════════════════════════════════════════════════════════════
Version installée : 0.1.0
Version disponible: 0.2.0
════════════════════════════════════════════════════════════

📝 Fichiers qui seront mis à jour:

  • app/javascript/controllers/upload_d_n_d/uploads_controller.js
    └─ Controller Stimulus principal
  • app/assets/stylesheets/upload_d_n_d.css
    └─ Styles CSS (modales, dropzone, etc.)
  • app/components/upload_d_n_d/upload_component.rb
    └─ ViewComponent Ruby

⚠️  Fichiers qui NE seront PAS touchés:

  ✓ app/models/concerns/upload_d_n_d/uploadable.rb
  ✓ app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb
  ✓ app/helpers/upload_d_n_d/upload_helper.rb
  ✓ config/initializers/upload_d_n_d.rb
  ✓ app/models/**/*.rb

Continuer avec la mise à jour ? (y/n) y

🔄 Mise à jour des fichiers...

  ✓ app/javascript/controllers/upload_d_n_d/uploads_controller.js
  ✓ app/assets/stylesheets/upload_d_n_d.css
  ✓ app/components/upload_d_n_d/upload_component.rb

✓ Version mise à jour: 0.2.0

════════════════════════════════════════════════════════════
  ✅ Mise à jour terminée avec succès !
════════════════════════════════════════════════════════════
```

## 🔧 Fonctionnement technique

### 1. Fichier de version

Le fichier `.upload_d_n_d_version` à la racine de votre app contient simplement :
```
0.2.0
```

### 2. Détection des changements

Le système compare les checksums MD5 des fichiers installés avec ceux de la gem.

### 3. Mise à jour sélective

Seuls les fichiers **modifiés dans la gem** ET **présents dans votre app** sont mis à jour.

## ⚙️ Configuration

### Désactiver les notifications

Si vous ne voulez pas voir les notifications au démarrage :

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  # ... autres configs
end

# Désactive la vérification des mises à jour
UploadDND::VersionTracker.instance_variable_set(:@silent, true)
```

### Environnements

Par défaut, les notifications ne s'affichent **qu'en développement**.

En production, vous devez lancer manuellement :
```bash
RAILS_ENV=production rails g upload_d_n_d:update
```

## 🛡️ Sécurité

- ✅ **Aucune modification automatique** : l'utilisateur doit lancer explicitement `update`
- ✅ **Confirmation requise** : sauf si `--force` est utilisé
- ✅ **Dry-run disponible** : `--dry-run` pour simuler
- ✅ **Fichiers préservés** : vos modèles et configs ne sont jamais touchés
- ✅ **Checksums MD5** : détection fiable des changements

## 📚 Cas d'usage

### Mise à jour après `bundle update`

```bash
bundle update upload_d_n_d
rails server  # Affiche la notification
rails g upload_d_n_d:update
```

### Mise à jour forcée (CI/CD)

```bash
rails g upload_d_n_d:update --force
```

### Vérifier sans modifier

```bash
rails g upload_d_n_d:update --dry-run
```

## 🐛 Troubleshooting

### "Aucun fichier à mettre à jour" mais la version est obsolète

Le fichier `.upload_d_n_d_version` n'existe peut-être pas. Créez-le manuellement :

```bash
echo "0.1.0" > .upload_d_n_d_version
```

Puis relancez :
```bash
rails g upload_d_n_d:update
```

### J'ai modifié un fichier tracké

Si vous avez personnalisé un fichier qui est normalement mis à jour automatiquement (ex: `uploads_controller.js`), deux options :

1. **Accepter la mise à jour** et réappliquer vos modifications
2. **Copier le fichier ailleurs** et le personnaliser dans votre app

### La notification ne s'affiche pas

Vérifiez que :
1. Vous êtes en environnement `development`
2. Le fichier `.upload_d_n_d_version` existe
3. Rails démarre complètement (pas d'erreur avant)

## 📝 Changelog

Consultez le [CHANGELOG.md](../CHANGELOG.md) pour voir les modifications entre chaque version.
