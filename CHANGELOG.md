# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Interface drag & drop intuitive avec barre de progression
- Validation sécurisée côté serveur (MIME type, taille, nombre de fichiers)
- Support d'upload temporaire pour les formulaires de création
- Support multi-fichiers (has_one_attached et has_many_attached)
- Autorisation flexible (Pundit, CanCanCan, ou custom)
- Protection contre le spoofing de fichiers via détection MIME
- Logging et audit trail complet
- Configuration globale et par composant
- Générateur d'installation Rails avec configuration automatique
- Générateur de modèle avec injection automatique dans controllers et routes
- **Conversion automatique des extensions de fichiers en MIME types** (ex: `jpg` → `image/jpeg`)
- Module `MimeTypeHelper` avec support de 40+ extensions (images, documents, audio, vidéo, archives)
- Générateur de politique Pundit
- Concern `UploadDND::Uploadable` pour les modèles
- Concern `UploadDND::Controllers::Uploadable` pour les contrôleurs (séparé du concern modèle)
- Concern UploadAuthorization pour les contrôleurs (optionnel)
- Helper `upload_field` pour les vues
- Contrôleur Stimulus pour le drag & drop avec gestion d'erreurs complète
- Modèle TemporaryAttachment pour les uploads temporaires
- Template FileValidator optionnel
- Vues personnalisables copiées dans l'application hôte
- Support automatique de Stimulus (enregistrement dans le manifest)
- Support automatique du CSS (import dans application.css)
- Documentation complète dans le README et GENERATOR_EXAMPLES

### Changed
- **BREAKING**: Le concern contrôleur a été renommé de `UploadDND::Uploadable` à `UploadDND::Controllers::Uploadable` pour éviter les conflits avec le concern modèle
- **L'option `--content_type` accepte maintenant les extensions de fichiers** (ex: `jpg png pdf`) au lieu des MIME types pour une meilleure UX développeur
- Les MIME types sont toujours supportés pour compatibilité
- Les vues sont maintenant copiées dans l'application hôte au lieu d'utiliser uniquement les vues de la gem (permet l'override facile)
- Le controller Stimulus est maintenant automatiquement enregistré dans le manifest
- Les styles CSS sont maintenant copiés dans l'application hôte, sans modification automatique du stylesheet principal
- La suppression de fichiers persistés utilise maintenant les routes de l'application hôte (ex: `/projects/:id/remove_file`) au lieu des routes de la gem
- Utilisation de Warden pour récupérer `current_user` dans le controller de la gem (compatible Devise)
- Le résumé du générateur affiche maintenant à la fois les extensions ET les MIME types convertis

### Fixed
- Ajout de la méthode `handleDragEnter` manquante dans le contrôleur Stimulus
- Gestion des erreurs HTTP dans les méthodes `attachBlob` et `confirmDelete`
- Correction de l'utilisation de `attachment.id` au lieu de `blob.id` dans `_files_list.html.erb`
- Correction du routing pour la suppression de fichiers (DELETE au lieu de GET)
- Ajout de `include Pundit::Authorization` dans le controller de la gem
- Correction de `current_user` qui retournait nil (utilisation de Warden)
- Le générateur de modèle est maintenant non-invasif (snippets à copier/coller) pour éviter les modifications automatiques des modèles, routes et controllers existants
- Suppression des méthodes dupliquées dans `model_generator.rb`
- Correction de la structure de namespace pour les concerns controllers
- **Le générateur détecte maintenant les attributs uploadables existants** et ne duplique pas le concern
- **Ajout intelligent de nouvelles sections dans `_uploads.html.erb`** sans écraser l'existant
- Le générateur vérifie maintenant si chaque élément existe avant de l'ajouter (concern, association, attribut uploadable)
- **CRITIQUE: Le concern est maintenant injecté au DÉBUT de la classe** (juste après la déclaration) au lieu de la fin
  - Résout l'erreur `undefined method 'uploadable'` lors des migrations
  - Ordre correct : 1) include concern, 2) has_*_attached, 3) uploadable
- L'association ActiveStorage est maintenant injectée juste après le concern pour un ordre logique
- Correction de l'affichage du code à ajouter dans les vues (utilisait `puts` avec `%%` au lieu de `say`)
- **Support de Tailwind CSS** : détection automatique et utilisation de `stylesheet_link_tag` au lieu de `@import`
  - Évite les erreurs avec PostCSS et Tailwind
  - Le générateur affiche l'instruction à ajouter dans le layout si Tailwind est détecté
- **Alertes simplifiées** : Utilisation des alertes natives du navigateur (`alert()`, `confirm()`)
  - SweetAlert2 reste supporté si disponible
  - Plus de dépendance CSS personnalisée pour les alertes
  - Compatibilité avec les systèmes de flash existants
- **Affichage intelligent des types de fichiers acceptés** dans la zone drag & drop
  - Le composant lit maintenant la configuration `uploadable` du modèle
  - Affiche uniquement les extensions configurées pour l'attribut spécifique
  - Conversion automatique MIME types → extensions (ex: `application/pdf` → `.pdf`)
  - Fini l'affichage générique de tous les formats possibles

### Security
- Validation des paramètres pour empêcher l'injection
- Protection CSRF automatique
- Isolation des fichiers temporaires par session
- Vérification des signatures de blob
- Détection de spoofing MIME avec Marcel
- Sanitization des noms de fichiers
- Vérification de format des signed_blob_id
- Vérification de propriété des fichiers avant suppression

## [0.1.0] - 2026-01-01

### Added
- Initial release
- Basic drag & drop functionality
- ActiveStorage integration
- Stimulus controller
- ViewComponent integration
