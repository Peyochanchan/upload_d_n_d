# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.1] - 2026-07-09

### Security
- **Fail-open d'autorisation dans `Controllers::Uploadable`** : `authorize_record_for_update` testait `respond_to?(:authorize)` sans `include_all: true` — `Pundit::Authorization#authorize` étant privée, le check échouait et `attach_file`/`remove_file` s'exécutaient sans aucune vérification d'autorisation (puis 500 `verify_authorized` après exécution). Mise à jour fortement recommandée depuis 0.6.0 et antérieures.

## [0.6.0] - 2026-07-09

Version issue d'un audit sécurité/qualité de la gem.

### Security
- **Modale de prévisualisation réécrite en DOM APIs** : corrige un XSS possible via un nom de fichier forgé interpolé dans `innerHTML` (breakout d'attribut)
- **Rate limiting** : compteur atomique via `Rails.cache.increment` (le read + write laissait passer des requêtes concurrentes sous la limite)
- **README** : nouvelle documentation sécurité — protection de l'endpoint DirectUpload (`/rails/active_storage/direct_uploads`, hors périmètre du rate limiting de la gem) et dimensionnement du rate limiting

### Fixed
- **Boutons des modales alert/confirm inertes** : les `data-action` posés sur du DOM appendu à `document.body` n'étaient jamais bindés par Stimulus (hors scope du controller) — remplacés par des event listeners directs ; le clic sur l'overlay pour fermer fonctionne désormais
- Preview PDF via `<object>` avec fallback téléchargement natif (iframe vide sur Safari mobile auparavant)
- Suppression des styles inline injectés en JS (compatibilité CSP `style-src` stricte)
- `delete_url` des listes de fichiers construit via `polymorphic_path` (respecte namespaces, scopes de locale, `relative_url_root` ; échappe les query params)
- Validation d'extension côté client en comparaison exacte (`.jpe` passait si `.jpeg` était accepté)

### Added
- **URLs de blobs via `resolve_model_to_route`** : la gem suit le réglage `config.active_storage.resolve_model_to_route` de l'app hôte — passez-le à `:rails_storage_proxy` pour servir les blobs en same-origin (CSP stricte, bucket S3-like externe), sans configuration côté gem
- **`UploadDND::CleanupTemporaryAttachmentsJob`** : job de purge des fichiers temporaires expirés embarqué dans la gem (plus besoin de l'écrire côté app, il ne reste que la planification)
- Accessibilité de la modale de prévisualisation : `role="dialog"`, `aria-modal`, `aria-labelledby`, focus trap, retour du focus au déclencheur
- i18n des libellés de la modale de prévisualisation (fr + en)
- Fermeture des modales sur `turbo:before-visit` (plus de modale orpheline après navigation)

### Changed
- Icônes de fichiers centralisées dans le partial `upload_d_n_d/shared/_file_icon` — surchargeable par l'app hôte en le shadowant

## [0.5.0] - 2026-03-26

Refonte majeure de l'architecture : tous les assets (JS, CSS, ViewComponent) sont désormais servis directement depuis la gem. Plus besoin de copier des fichiers dans l'app hôte. Un simple `bundle update` suffit pour tout mettre à jour.

### Changed
- **Contrôleurs Stimulus** : servis depuis la gem via importmap, auto-enregistrés avec `import "upload_d_n_d"`
- **CSS** : servi depuis la gem via l'asset pipeline (`stylesheet_link_tag "upload_d_n_d/application"`)
- **ViewComponent** : servi directement depuis la gem (plus copié dans l'app)
- **Install generator** : ne copie plus JS, CSS ni Component ; affiche uniquement les instructions d'import
- **POST_INSTALL** : mis à jour pour refléter la nouvelle architecture

### Removed
- `VersionTracker` : plus besoin de tracker les versions des fichiers copiés (il n'y en a plus)
- `UpdateGenerator` (`rails g upload_d_n_d:update`) : plus nécessaire
- Fichier `.upload_d_n_d_version` dans l'app hôte : plus nécessaire
- Documentation `UPDATE_SYSTEM.md` : obsolète

### Added
- Auto-enregistrement des contrôleurs Stimulus via `window.Stimulus`
- Pin importmap `upload_d_n_d` comme point d'entrée unique
- Détection et nettoyage des anciens fichiers copiés (STALE_OVERRIDES étendu)
- Specs du install generator (20 tests)
- Specs d'intégration engine assets (14 tests)

### Migration depuis v0.4.x
Voir le [guide de migration](MIGRATION_0.5.md) pour les instructions détaillées.

## [0.4.1] - 2026-03-25

### Changed
- Bump version, require Ruby >= 3.2

## [0.4.0] - 2026-03-24

### Changed
- Les modules critiques (`Uploadable`, `Controllers::Uploadable`, `FileValidator`) sont fournis par le runtime de la gem
- Les vues sont servies directement depuis la gem
- Remplacement des icônes Font Awesome par des SVG inline Lucide

### Added
- Système `VersionTracker` + `UpdateGenerator` pour synchroniser les fichiers copiés
- Nettoyage automatique des anciennes copies (concerns) lors de l'installation

## [0.1.0] - 2026-01-05

Première version stable de UploadDND, un système de drag & drop sécurisé pour Rails.

### Added

#### Fonctionnalités principales
- Interface drag & drop intuitive avec barre de progression
- Support multi-fichiers (has_one_attached et has_many_attached)
- Upload temporaire pour les formulaires de création (avant persistance du modèle)
- Prévisualisation des fichiers (images et PDF) côté client

#### Validation et sécurité
- Validation sécurisée côté serveur (MIME type, taille, nombre de fichiers)
- Protection contre le spoofing de fichiers via détection MIME avec Marcel
- Protection CSRF automatique
- Isolation des fichiers temporaires par session
- Sanitization des noms de fichiers
- Vérification des signatures de blob

#### Autorisation
- Support flexible d'autorisation (Pundit, CanCanCan, ou custom)
- Générateur de politique Pundit
- Concern `UploadDND::Controllers::UploadAuthorization` pour les contrôleurs

#### Configuration
- Configuration globale et par composant
- Module `MimeTypeHelper` avec support de 40+ extensions (images, documents, audio, vidéo, archives)
- Conversion automatique des extensions de fichiers en MIME types (ex: `jpg` → `image/jpeg`)
- Styles CSS personnalisables avec variables CSS
- Callbacks personnalisables (on_upload_success, on_upload_error)

#### Intégration Rails
- Compatible Rails 7 et 8
- Concern `UploadDND::Uploadable` pour les modèles
- Concern `UploadDND::Controllers::Uploadable` pour les contrôleurs
- Helper `upload_field` pour les vues
- Contrôleur Stimulus pour le drag & drop
- Modèle TemporaryAttachment pour les uploads temporaires
- Support automatique de Stimulus et des assets

#### Générateurs
- Générateur d'installation avec configuration automatique
  - Installation des dépendances (view_component, stimulus-rails)
  - Migration pour les fichiers temporaires
  - Copie des concerns, helpers et contrôleurs Stimulus
  - Styles CSS (compatible Tailwind et Asset Pipeline)
  - Configuration initiale
- Générateur de modèle
  - Support des namespaces (Admin::Article, Manager::Report, etc.)
  - Options configurables (--multiple, --content_type, --max_size, --max_files)
  - Génération optionnelle de controller et vues
  - Détection intelligente des attributs uploadables existants

#### Documentation
- README complet avec exemples
- Guide d'autorisation détaillé
- Exemples de générateurs
- Documentation de test

### Security
- Validation des paramètres pour empêcher l'injection
- Protection CSRF automatique
- Isolation des fichiers temporaires par session
- Vérification des signatures de blob
- Détection de spoofing MIME avec Marcel
- Sanitization des noms de fichiers
- Vérification de propriété des fichiers avant suppression
