# Migration vers UploadDND v0.5.0

## Qu'est-ce qui change ?

Avant la v0.5.0, le générateur `install` copiait des fichiers dans votre app :
- `app/javascript/controllers/upload_d_n_d/uploads_controller.js`
- `app/javascript/controllers/upload_d_n_d/preview_controller.js`
- `app/assets/stylesheets/upload_d_n_d.css`
- `app/components/upload_d_n_d/upload_component.rb`
- `app/components/upload_d_n_d/upload_component.html.erb`

**Depuis la v0.5.0**, ces fichiers sont servis directement depuis la gem. Les copies locales ne sont plus nécessaires et **shadowent** les versions de la gem si elles restent en place.

## Étape 1 : Mettre à jour la gem

```bash
bundle update upload_d_n_d
```

## Étape 2 : Supprimer les fichiers copiés

Supprimez ces fichiers de votre app (s'ils existent) :

```bash
# Contrôleurs Stimulus (servis depuis la gem)
rm -f app/javascript/controllers/upload_d_n_d/uploads_controller.js
rm -f app/javascript/controllers/upload_d_n_d/preview_controller.js

# CSS (servi depuis la gem)
rm -f app/assets/stylesheets/upload_d_n_d.css

# ViewComponent (servi depuis la gem)
rm -f app/components/upload_d_n_d/upload_component.rb
rm -f app/components/upload_d_n_d/upload_component.html.erb

# Fichier de version (plus nécessaire)
rm -f .upload_d_n_d_version
```

Vous pouvez aussi supprimer les dossiers vides :

```bash
rmdir app/javascript/controllers/upload_d_n_d 2>/dev/null
rmdir app/components/upload_d_n_d 2>/dev/null
```

> **Alternative** : relancez `rails g upload_d_n_d:install`. Le générateur détectera les anciens fichiers et proposera de les supprimer automatiquement.

## Étape 3 : Configurer l'import JavaScript

Remplacez l'ancien enregistrement Stimulus dans `app/javascript/controllers/index.js` :

```diff
- import UploadDNDUploadsController from "./upload_d_n_d/uploads_controller"
- application.register("upload-d-n-d--uploads", UploadDNDUploadsController)
- import UploadDNDPreviewController from "./upload_d_n_d/preview_controller"
- application.register("upload-d-n-d--preview", UploadDNDPreviewController)
```

Par un simple import dans `app/javascript/application.js` :

```js
import "upload_d_n_d"
```

Les contrôleurs Stimulus sont auto-enregistrés. Si vous utilisiez `stimulus:manifest:update`, vous pouvez le relancer pour qu'il supprime les références aux anciens fichiers.

## Étape 4 : Configurer le CSS

Remplacez l'ancien import CSS. Selon votre setup :

**Avant (Sprockets / import CSS)** :
```diff
- @import 'upload_d_n_d.css';
```

**Après (dans votre layout)** :
```erb
<%= stylesheet_link_tag "upload_d_n_d/application", media: "all" %>
```

## Étape 5 : Vérifier

1. Lancez votre serveur : `rails s`
2. Vérifiez qu'il n'y a **plus** de notification VersionTracker au démarrage
3. Testez un upload pour vérifier que tout fonctionne

## Fichiers que vous devez garder

Ces fichiers sont personnalisables et restent dans votre app :

| Fichier | Rôle |
|---------|------|
| `app/controllers/concerns/upload_d_n_d/upload_authorization.rb` | Logique d'autorisation (Pundit, CanCanCan, custom) |
| `app/helpers/upload_d_n_d/upload_helper.rb` | Helper `upload_field` |
| `config/initializers/upload_d_n_d.rb` | Configuration globale |

## Résumé

| Avant (v0.4.x) | Après (v0.5.0) |
|-----------------|----------------|
| JS copié dans l'app, enregistrement manuel | `import "upload_d_n_d"` dans application.js |
| CSS copié dans l'app | `stylesheet_link_tag "upload_d_n_d/application"` |
| ViewComponent copié dans l'app | Servi depuis la gem |
| `rails g upload_d_n_d:update` après chaque `bundle update` | Plus nécessaire |
| `.upload_d_n_d_version` dans l'app | Supprimé |
