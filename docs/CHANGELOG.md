# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.3] - 2026-10-16

Correctif de sécurité (un fichier déjà rattaché ne peut plus être rattaché ailleurs) et purge des fichiers refusés après l'envoi direct. **Mise à jour recommandée.**

### Security
- **Un fichier déjà rattaché pouvait être rattaché une seconde fois** : `POST /upload_d_n_d/temporary_attachments`, `POST /upload_d_n_d/attachments` et `Controllers::Uploadable#attach_file` acceptaient le `signed_id` d'un blob déjà rattaché à un autre record (ou gardé par un fichier temporaire). Ce `signed_id` figure dans chaque URL de fichier (`/rails/active_storage/blobs/...`) : un utilisateur qui l'obtenait pouvait rattacher le fichier d'un autre à ses propres records, et le fichier restait accessible même après sa suppression par son propriétaire. Un tel blob est désormais refusé (422, `upload_d_n_d.errors.blob_already_attached`), après l'autorisation et avant toute écriture

### Fixed
- **Blobs orphelins à chaque refus** : avec DirectUpload, le fichier est déjà dans le bucket quand la gem le contrôle. Un refus (taille, type, MIME strict, validation du modèle, erreur à l'enregistrement du fichier temporaire ou de l'attachement) laissait le blob en place, et chaque nouvel essai en ajoutait un. Le blob refusé est désormais purgé en arrière-plan (`UploadDND::PurgeRejectedBlobJob`), sur `POST /upload_d_n_d/temporary_attachments`, `POST /upload_d_n_d/attachments` et `Controllers::Uploadable#attach_file`

### Added
- **`config.rejected_blob_purge_window`** (1 heure par défaut) : seul un blob créé dans cette fenêtre est purgé au refus. `nil` désactive la purge

### Notes
- Garde-fous : un blob rattaché à un record ou à un fichier temporaire n'est jamais supprimé, ni au refus ni à l'exécution du job (revérifié). Un blob plus ancien que la fenêtre est conservé (il peut être cité dans un HTML stocké). Rien n'est supprimé si l'autorisation n'a pas été explicitement accordée : refus (401, 403) ou autorisation qui n'aboutit pas (exception, policy absente)
- Le job utilise la file `active_storage.queues.purge`, comme `ActiveStorage::PurgeJob` : rien à configurer si la purge Active Storage fonctionne déjà
- Les blobs orphelins déjà présents ne sont pas concernés : leur nettoyage est prévu séparément
- **Pour les apps** : un `signed_id` accepté jusqu'ici peut désormais être refusé. Le composant n'envoie que des fichiers fraîchement déposés et n'est pas concerné. Une app qui réutilise volontairement un fichier existant (duplication d'un record par `signed_id`, par exemple) doit le faire hors des endpoints de la gem (`record.file.attach(blob)` côté serveur) — ou, pour une vraie copie, passer par `blob.open` + `attach(io:)`

## [0.7.2] - 2026-10-16

Correctif de sécurité. **Mise à jour fortement recommandée depuis toutes les versions antérieures.**

### Security
- **Appel de méthode arbitraire via `attribute_name`** : le nom d'attribut venu du client était résolu par `respond_to?` + `send`. Un nom comme `destroy`, `delete` ou `touch` passait le contrôle de format et était appelé sur le record : via `POST /upload_d_n_d/attachments`, tout utilisateur autorisé à uploader pouvait supprimer le record désigné par `record_gid`, quel que soit son modèle. Seuls les attachments déclarés (`has_one_attached` / `has_many_attached`) sont désormais résolus (`UploadDND::AttachmentLookup`), dans `AttachmentsController#create`, `Controllers::Uploadable#attach_file` et le transfert des fichiers temporaires (`Uploadable#attach_temporary_uploads`, `TemporaryAttachment.attach_to_record`)
- **Upload sur un record sans autorisation sur ce record** : `POST /upload_d_n_d/attachments` ne vérifiait que la policy générique `UploadDNDAttachmentPolicy#create?`. Tout utilisateur autorisé à uploader pouvait attacher un fichier à n'importe quel record et recevoir la liste de ses fichiers. La policy du record (`update?`) est maintenant vérifiée après la policy générique, comme pour la suppression

### Notes
- Avec Pundit : un utilisateur dont la policy du record refuse `update?` reçoit désormais 403 à l'upload sur ce record. Les modèles sans policy gardent le comportement précédent (policy générique seule)
- Un `attribute_name` qui n'est pas un attachment du modèle renvoie 422 (comme un attribut inexistant auparavant). Un fichier temporaire portant un tel nom est supprimé au transfert, sans effet sur le record

## [0.7.1] - 2026-08-26

Les fichiers déposés dans un formulaire de création survivent au rechargement de page, et l'app peut les purger à l'annulation.

### Fixed
- **Upload impossible sur une session vierge** — sans cookie de session, `session.id` était nil : le premier upload d'un formulaire de création échouait en 422 (`session_id` vide), et l'id lu au rendu du composant ne correspondait pas à celui des uploads. `UploadDND::SessionId.for(session)` amorce désormais la session avant de lire l'id ; utilisé partout dans la gem et dans les templates du générateur (`upload_session_field`, concern, authorization)
- **Composant : zone vide après rechargement** — sans record persisté, le composant rend maintenant les fichiers temporaires de la session courante (`UploadComponent#files` existait mais n'était jamais appelé par le template). F5, restauration de brouillon ou reconnexion n'affichent plus une zone vide alors que les fichiers sont côté serveur

### Added
- **`GET /upload_d_n_d/temporary_attachments?attribute_name=x`** : HTML de la liste des fichiers temporaires de la session, pour les apps qui remplacent la zone hors composant
- **`DELETE /upload_d_n_d/temporary_attachments?attribute_name=x`** : purge des fichiers temporaires de la session pour cet attribut (bouton « Annuler »), 204. Soumis à la policy `destroy?` si Pundit est activé

### Notes
- Les fichiers d'un formulaire abandonné sans purge réapparaissent dans tout formulaire suivant de la session utilisant le même `attribute_name`, jusqu'à `temporary_files_retention`. Auparavant ils étaient invisibles mais attachés quand même au submit

## [0.7.0] - 2026-07-17

La suppression de fichiers passe par le moteur de la gem, comme l'upload : **plus aucune route requise côté app**, quel que soit le routing du record (imbriqué, singulier, namespacé). Les `resolve()` déclarés pour la gem deviennent inutiles (ils restent utiles au routing polymorphique du reste de votre app).

### Changed
- **⚠️ `config.delete_route` par défaut `:engine`** : l'UI de suppression appelle `DELETE /upload_d_n_d/attachments/:id` (moteur) au lieu de la route membre `remove_file` de l'app. Les actions `remove_file` custom ne sont plus appelées par l'UI — branchez `config.on_file_removed` ou repassez en `config.delete_route = :host` (flux legacy inchangé)
- `UploadDND::UnroutableRecordError` et le pattern `resolve()` ne concernent plus que le mode `:host`

### Added
- **`AttachmentsController#destroy`** : suppression par `record_gid`, autorisation fail-closed via la policy Pundit du record (`update?`) avec fallback sur la policy générique de la gem, vérification d'appartenance attachment ↔ record ↔ attribut
- **`config.on_file_removed`** : callback `->(record, attribute_name, user)` après suppression
- **`config.delete_route`** : `:engine` (défaut) / `:host` (legacy)

## [0.6.2] - 2026-07-17

Support des records en resources imbriquées ou singulières (ex. `resource :convention` sous `resources :projects`).

### Added
- **`UploadDND::UnroutableRecordError`** : quand un record affiché dans la liste de fichiers n'a pas de route polymorphique, la gem lève une erreur explicite contenant le remède (déclarer `resolve()` dans `config/routes.rb`, exemple inclus) au lieu d'un `undefined method 'xxx_path'` cryptique
- **Helper `udnd_remove_file_url(record, attachment, attribute_name)`** : point d'extension officiel pour l'URL de suppression, surchargeable dans le `ApplicationHelper` de l'app — ne shadowez plus le partial `_files_list` pour ça
- Section README « Records imbriqués ou resources singulières » (pattern `resolve`)

### Fixed
- **`authorize_record_for_update` : fallback sur la policy top-level** quand la policy namespacée n'existe pas. Le concern cherchait la policy dans le namespace du controller (`Projects::ConventionsController` → `Projects::ConventionPolicy`) alors qu'un `module:` de routes n'implique pas un namespace de policies — `Pundit::NotDefinedError` déclenche désormais une seconde tentative sur la policy top-level (`ConventionPolicy`). Les autres erreurs d'autorisation ne sont pas avalées.

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
