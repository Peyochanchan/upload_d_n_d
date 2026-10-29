# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.1] - 2026-10-29

### Changed
- Documentation : clarifications mineures.

## [0.9.0] - 2026-10-29

Lot post-0.8.0 : nettoyage opt-in des blobs orphelins, CI matricielle avec audit des CVE, et deux correctifs — dont `strict_mime_check` désormais utilisable avec un champ fichier classique. Version mineure, rétrocompatible. **Mise à jour recommandée.** les apps sous Pundit ou CanCanCan détecté automatiquement n'ont qu'à passer leur `tag:` à `v0.9.0` ; le nettoyage des orphelins est opt-in, rien n'est activé sans config.

### Added
- **Nettoyage des blobs orphelins** (`UploadDND::OrphanBlobs`, `UploadDND::PurgeOrphanBlobsJob`, tâche rake `upload_d_n_d:purge_orphans`) : supprime, de façon opt-in, les blobs envoyés par DirectUpload mais jamais rattachés (refus, coupure réseau, onglet fermé). Un blob n'est supprimé que s'il n'a aucun rattachement, est plus vieux que `orphan_blob_min_age` (2 jours par défaut), n'est pas gardé par un fichier temporaire, et n'est **cité dans aucun texte de la base** (colonnes texte et JSON) — par clé du bucket, par `signed_id` ou par sgid ; jamais par le nom de fichier. La rake simule par défaut (`APPLY=1` pour supprimer), le job journalise un rapport par défaut (`apply: true` pour supprimer). Réglages : `orphan_blob_min_age`, `orphan_scan_columns` (liste blanche pour borner la mémoire), `orphan_scan_patterns`, `orphan_scan_excluded_tables`. PostgreSQL requis pour le scan des citations (sinon erreur explicite, jamais de suppression sans ce filet)
- **`view_component` déclaré en dépendance d'exécution** (`>= 3.0`) : `UploadComponent` en hérite, la dépendance était jusqu'ici implicite. Sans effet pour une app qui l'a déjà

### Changed
- **CI matricielle** : la CI teste désormais la plage de Rails déclarée (Ruby 3.2/3.3/3.4 × Rails 7.2/8.0/8.1, en diagonale plus un croisé), avec service PostgreSQL, et ajoute `bundler-audit` (audit des CVE). Dépendances de développement mises à jour pour les correctifs de sécurité (Rails 8.1.4, view_component 3.27, puma 8.0.2) — sans effet pour les apps, qui résolvent leur propre lock
- **Gemspec finalisé pour la publication open source** : borne Rails `>= 7.2.3, < 8.2` (seul Rails 8.1 est testé) ; métadonnées complètes (homepage, `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, MFA requise) pointant vers le dépôt GitHub public ; licence MIT ; e-mail de contact à jour ; dépendance de dev `rack-attack` retirée (le rate limiting s'appuie sur `Rails.cache`, pas sur rack-attack)
- **La gem embarque désormais son CHANGELOG** (`docs/CHANGELOG.md` ajouté à la liste de fichiers publiée). Nettoyage du dépôt : `node_modules/` n'est plus suivi, le squelette Minitest inutilisé est retiré (la suite est RSpec), `package.json` passe en 0.8.0

### Fixed
- **`strict_mime_check` avec un champ fichier classique** : avec un `file_field` ordinaire (le fichier part avec le formulaire, envoyé au stockage seulement après le `save`), la vérification anti-spoofing lisait le fichier depuis le stockage pendant la validation, donc avant son envoi. Le fichier n'y était pas encore → `ActiveStorage::FileNotFoundError`, traduit en « Impossible de vérifier le type de fichier » : tous les fichiers refusés. Le validateur lit désormais la source encore en attente (`attachment_changes`) quand le blob n'est pas encore stocké, et retombe sur le stockage sinon (zone de dépôt). Gère `has_one_attached` et `has_many_attached`. Aucun changement pour la zone de dépôt, déjà fonctionnelle. Même correction portée au template du générateur
- **Conseil dangereux du README** : la doc proposait `ActiveStorage::Blob.unattached.purge_later` sans garde-fou, ce qui supprime des envois en cours et des fichiers cités dans du HTML stocké hors Action Text. Remplacé par un renvoi vers le nettoyage sûr ci-dessus

### Notes
- **Montée de Rails** : la borne `< 8.2` empêche une app hôte de passer à Rails 8.2 tant qu'une version de la gem ne la relâche pas. Prévoir une release de la gem avant toute montée majeure de Rails côté app.

## [0.8.0] - 2026-10-19

Durcissement de la sécurité avant 1.0 : autorisation fail-closed, limites d'un champ appliquées côté serveur dès le dépôt, et statuts d'erreur corrects sur les réponses Turbo Stream. Version mineure, rétrocompatible, avec notes de migration (voir ci-dessous). **Mise à jour recommandée.** Les apps avec Pundit ou CanCanCan détecté automatiquement n'ont rien à changer.

### Security
- **Autorisation fail-closed** : la gem n'autorisait que si l'adaptateur valait `:pundit` et que Pundit était chargé. Dans tous les autres cas, uploads et suppressions passaient sans contrôle et sans avertissement : aucune librairie détectée (`nil`), `:cancancan` (détecté mais jamais implémenté), `:pundit` sans Pundit chargé. Côté concern `Controllers::Uploadable`, `attach_file` et `remove_file` sautaient l'autorisation quand le contrôleur n'avait pas de méthode `authorize`. Toute autorisation passe désormais par un port unique (`UploadDND::Authorization`). Sans adaptateur utilisable (`nil`, valeur inconnue), la requête est refusée (403). Un adaptateur déclaré mais inutilisable fait échouer la requête (500, `UploadDND::Authorization::ConfigurationError`)
- **Limites d'un champ appliquées au dépôt** : `POST /upload_d_n_d/attachments` et `Controllers::Uploadable#attach_file` n'appliquaient aucune limite de taille ni de type (seule la validation du modèle, à l'enregistrement, protégeait), et `POST /upload_d_n_d/temporary_attachments` n'appliquait que les limites globales. Le transfert des fichiers temporaires vers le record (`Uploadable#attach_temporary_uploads`, `TemporaryAttachment.attach_to_record`) ne validait rien : un fichier hors limites du champ y était attaché. Les limites du champ (`uploadable`) sont désormais vérifiées au dépôt sur les trois points d'entrée, et de nouveau au transfert (fichier écarté et journalisé). Un fichier refusé est purgé
- **Messages d'erreur** : `ActionController::BadRequest` et l'échec de détection MIME (contrôleur et `FileValidator`) ne renvoient plus le message de l'exception au client (`upload_d_n_d.errors.bad_request`, `upload_d_n_d.errors.mime_detection_failed` sans `%{message}`). Le détail reste dans les logs

### Fixed
- **Statut 200 sur un échec en Turbo Stream** : dans le concern `Controllers::Uploadable`, chaque réponse d'erreur en Turbo Stream rendait le flux sans statut (200), alors que la variante JSON renvoyait le bon code. Un client ne pouvait pas distinguer l'échec du succès sur le flux Turbo. Concerné : `attach_file` (échec d'enregistrement, désormais 422), `remove_file` (fichier absent ou refusé, 404), et les `rescue_from` `ActiveStorage::IntegrityError` et `ActiveStorage::UnrepresentableError` (422). `422 + turbo_stream` est l'idiome Rails/Turbo pour un envoi en échec
- **Limites différentes entre navigateur et serveur** : sur un formulaire de création, le composant affichait les limites du modèle quand le serveur appliquait les limites globales. Un fichier accepté par le navigateur pouvait être refusé au dépôt (champ plus large que la configuration globale), ou l'inverse. Le composant et les contrôleurs partagent désormais les mêmes limites (`UploadDND::FieldConstraints`)
- **Intégration importmap inopérante** : le moteur appelait `config.importmap.draw`, qui n'existe pas (`config.importmap` est un `OrderedOptions`, l'appel ne faisait rien). Une app sous importmap-rails n'obtenait aucun pin `upload_d_n_d` (`Failed to resolve module specifier "upload_d_n_d"`). Le moteur ajoute désormais son `config/importmap.rb` à `config.importmap.paths`. Avec Sprockets, le JS de la gem est aussi déclaré dans `upload_d_n_d_manifest.js` (sans quoi `AssetNotPrecompiledError`). Les apps qui chargent le JS par un bundler ne sont pas concernées
- **Fichiers `.jpeg` refusés par le navigateur** sur un champ déclaré `accept: [:jpg, :jpeg]` : seule la première extension d'un type MIME était proposée (`.jpg`). Toutes les extensions connues sont désormais listées

### Added
- **Référence de champ signée** (`field_ref`) émise par le composant et renvoyée au dépôt : le serveur en déduit le modèle et l'attribut, et applique leurs limites. Sans référence (ancien client, appel direct), les limites globales restent appliquées
- **Adaptateur CanCanCan** (`authorization_adapter = :cancancan`) : `authorize! action, sujet`, avec les sujets génériques `:upload_d_n_d_attachment` et `:upload_d_n_d_temporary_attachment` (voir `docs/AUTHORIZATION.md`). La détection automatique s'appuie désormais sur `CanCan::Ability` : `CanCanCan` n'est pas défini par la gem cancancan
- **`authorization_adapter = :none`** : désactivation explicite de l'autorisation (seule l'authentification est vérifiée)
- **Avertissement au démarrage** quand l'autorisation est désactivée (`:none`) ou qu'aucun adaptateur n'est utilisable

### Notes
- **Migration** :
  - les apps avec Pundit ou CanCanCan détecté n'ont rien à changer : les policies et l'erreur `Pundit::NotAuthorizedError` relancée par `attach_file` et `remove_file` sont inchangées ;
  - une app **sans librairie d'autorisation**, ou qui posait `config.authorization_adapter = nil`, voit désormais tous ses uploads refusés : déclarer `config.authorization_adapter = :none` pour retrouver le comportement précédent, ou installer Pundit ;
  - avec `:none`, `attach_file` et `remove_file` n'appellent plus `authorize`, même si le contrôleur le définit.
- **Migration (statuts Turbo Stream)** : `attach_file`, `remove_file` et les erreurs Active Storage renvoient désormais un statut d'erreur (422 ou 404) sur le flux Turbo Stream, au lieu de 200. Une app qui testait un 200 sur ces échecs doit attendre le statut d'erreur ; le `fetch` du composant détecte déjà l'erreur par `response.ok`.
- **Migration (limites des champs)** :
  - un fichier hors limites du champ est désormais refusé dès le dépôt (422) au lieu de l'être à l'enregistrement du formulaire ;
  - sur un record existant, un champ sans `uploadable` reçoit les limites globales au dépôt (`config.max_size`, `config.accepted_types`), qui n'y étaient pas appliquées ;
  - sur un formulaire de création, passer `record:` (un record neuf) à `upload_field` pour que les limites du modèle s'appliquent ; sans `record:`, ce sont les limites globales ;
  - `accepted_types:` et `max_size:` passés à `upload_field` ne changent que l'affichage : une valeur plus large que le modèle est refusée par le serveur ;
  - les apps qui appellent les endpoints sans passer par le composant gardent les limites globales sur les fichiers temporaires.
- L'ancienne méthode « autorisation personnalisée » de `docs/AUTHORIZATION.md` (surcharger `authorize_upload_d_n_d_create!` dans l'ApplicationController) n'a jamais été appelée par la gem : elle est retirée de la documentation

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
