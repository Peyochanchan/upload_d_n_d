# UploadDND

Un système de drag & drop sécurisé et élégant pour vos applications Rails, basé sur ActiveStorage, Stimulus et ViewComponent.

## Fonctionnalités

- **Interface drag & drop intuitive** avec barre de progression
- **Validation sécurisée côté serveur** (MIME type, taille, nombre de fichiers)
- **Upload temporaire** pour les formulaires de création (avant persistance)
- **Support multi-fichiers** (has_one_attached et has_many_attached)
- **Autorisation flexible** (Pundit, CanCanCan, ou custom)
- **Protection contre le spoofing** de fichiers via détection MIME
- **Logging et audit trail** complet
- **Configuration globale et par composant**
- **Compatible Rails 7 et 8**

## Installation

### 1. Ajoutez la gem à votre Gemfile

```ruby
gem "upload_d_n_d"
```

### 2. Installez la gem

```bash
bundle install
```

### 3. Lancez le générateur d'installation

```bash
rails generate upload_d_n_d:install
```

Le générateur va :
- Vérifier et ajouter `view_component` et `stimulus-rails` au Gemfile si nécessaire
- Créer la migration pour les fichiers temporaires
- Installer le helper et le fichier d'autorisation (personnalisables)
- Monter les routes du moteur
- Créer le fichier de configuration
- (Optionnel) Générer la policy Pundit si Pundit est détecté

> **Architecture v0.5.0** : Tout est servi depuis la gem (JS, CSS, ViewComponent, concerns). Aucun fichier n'est copié dans l'app hôte (sauf le helper et l'autorisation, qui sont personnalisables). Un simple `bundle update` suffit pour mettre à jour.
>
> **Migration depuis v0.4.x ?** Voir le [guide de migration](docs/MIGRATION_0.5.md).

### 4. Lancez la migration

```bash
rails db:migrate
```

### 5. Configurez ActiveStorage

Si ce n'est pas déjà fait, installez et configurez ActiveStorage :

```bash
rails active_storage:install
rails db:migrate
```

#### URLs des blobs : redirect ou proxy

Les URLs de prévisualisation et de téléchargement suivent le réglage standard
`config.active_storage.resolve_model_to_route` de votre application :

- `:rails_storage_redirect` (défaut Rails) — redirection vers une URL signée
  temporaire du service de stockage (S3, etc.)
- `:rails_storage_proxy` — les fichiers sont servis par votre application,
  en same-origin

Avec un bucket S3-like externe et une CSP stricte (`frame-src 'self'`,
`img-src 'self'`), le mode redirect casse les prévisualisations. Passez en
mode proxy :

```ruby
# config/application.rb ou config/environments/production.rb
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

Aucune configuration côté gem : elle respecte ce réglage partout (previews,
API JSON).

## Configuration

Éditez `config/initializers/upload_d_n_d.rb` :

```ruby
UploadDND.configure do |config|
  # Taille maximale par défaut (peut être surchargée par composant)
  config.max_size = 10.megabytes

  # Types de fichiers acceptés par défaut
  config.accepted_types = '.pdf,.doc,.docx,.jpg,.jpeg,.png,.gif'

  # Couleur du thème
  config.main_color = '#E97451'

  # Durée de conservation des fichiers temporaires (en jours)
  config.temporary_files_retention = 7

  # Rate limiting (protection contre les abus)
  config.rate_limit_enabled = true         # Activer/désactiver le rate limiting
  config.rate_limit_max_requests = 10      # Nombre max de requêtes
  config.rate_limit_period = 60            # Période en secondes

  # Callbacks personnalisés
  config.on_upload_success = ->(blob, user) {
    Rails.logger.info "File uploaded: #{blob.filename} by #{user&.email}"
  }
  config.on_file_removed = ->(record, attribute_name, user) {
    Rails.logger.info "File removed from #{record.class}##{record.id} by #{user&.id}"
  }

  # Route de suppression : :engine (défaut, aucune route requise côté app)
  # ou :host (legacy, route membre remove_file de votre app)
  # config.delete_route = :engine
end
```

## Usage rapide avec le générateur

### Commande magique : `rails generate upload_d_n_d:model`

Le moyen le plus rapide de configurer un modèle avec drag & drop :

```bash
# Configuration basique - 1 seule commande!
rails g upload_d_n_d:model User --attribute=avatar

# Upload multiple avec namespace
rails g upload_d_n_d:model Admin::Article --attribute=images --multiple

# Fichiers PDF volumineux
rails g upload_d_n_d:model Manager::Report \
  --attribute=pdf_file \
  --content_type=pdf \
  --max_size=50
```

### Exemples d'utilisation

```bash
# 💼 Avatar utilisateur
rails g upload_d_n_d:model User --attribute=avatar

# 📸 Galerie de photos (max 10 images)
rails g upload_d_n_d:model Product \
  --attribute=photos \
  --multiple \
  --max_files=10

# 📄 Documents Office dans namespace Admin
rails g upload_d_n_d:model Admin::Article \
  --attribute=documents \
  --multiple \
  --content_type=pdf doc docx \
  --max_size=20

# 🎨 Images WebP uniquement
rails g upload_d_n_d:model Post \
  --attribute=cover_image \
  --content_type=webp

# ⚙️ Seulement le modèle (pas de controller/vues)
rails g upload_d_n_d:model User \
  --attribute=avatar \
  --no-controller \
  --no-views
```

### 🔍 Options disponibles

| Option | Description | Défaut | Exemple |
|--------|-------------|--------|---------|
| `--attribute` | Nom de l'attribut (requis) | - | `--attribute=avatar` |
| `--multiple` | Upload multiple fichiers | `false` | `--multiple` |
| `--content_type` | Extensions de fichiers acceptées | `jpg png` | `--content_type=pdf doc docx` (ou `--content_type=pdf,doc,docx`) |
| `--max_size` | Taille max en MB | `5` | `--max_size=50` |
| `--max_files` | Nombre max de fichiers | `nil` | `--max_files=10` |
| `--no-controller` | Ne pas afficher les instructions controller | `false` | `--no-controller` |
| `--no-views` | Ne pas afficher les instructions vues | `false` | `--no-views` |

> **Note** : L'option `--content_type` accepte les **extensions de fichiers** (ex: `jpg png pdf`) qui sont automatiquement converties en MIME types.
> Vous pouvez les passer séparées par **espaces** ou par **virgules** (ex: `pdf,docx,pptx`).
> Les MIME types restent acceptés si vous préférez (ex: `application/pdf`).

### 📝 Ce que fait le générateur

Le générateur `upload_d_n_d:model` est **non-invasif** et fournit des **instructions claires** pour :

1. **Modèle** : affiche le code à ajouter (concern, association ActiveStorage, configuration uploadable)
2. **Controller** : affiche les instructions pour inclure le concern `UploadDND::Controllers::Uploadable` et ajouter les actions `attach_file` et `remove_file`
3. **Routes** : affiche les routes à ajouter dans votre `config/routes.rb`
4. **Vues** : affiche comment utiliser le helper `upload_field` dans vos formulaires

**Aucun fichier n'est modifié automatiquement**, vous gardez le contrôle total. Les vues (liste de fichiers, preview) sont **fournies par la gem** et n'ont pas besoin d'être générées.

### Documentation complète

Pour plus d'exemples et de scénarios : voir [GENERATOR_EXAMPLES.md](docs/GENERATOR_EXAMPLES.md)

Pour l'aide en ligne de commande :
```bash
rails g upload_d_n_d:model --help
```

## Usage manuel (sans générateur)

### 1. Préparez votre modèle

```ruby
class User < ApplicationRecord
  include UploadDND::Uploadable

  # Pour un seul fichier (has_one_attached déclaré automatiquement)
  uploadable :avatar,
             accept: [:jpg, :png],
             max_size: 5.megabytes,
             strict_mime_check: true

  # Pour plusieurs fichiers (has_many_attached déclaré automatiquement)
  uploadable :documents,
             accept: [:pdf],
             max_size: 10.megabytes,
             multiple: true,
             max_files: 5,
             strict_mime_check: true
end
```

> **Note v0.4.0** : `uploadable` déclare automatiquement `has_one_attached` / `has_many_attached`.
> Utilisez `accept:` avec des symboles d'extension (`:jpg`, `:pdf`, etc.) au lieu de strings MIME.
> Les strings MIME restent acceptées via `content_type:` pour la rétrocompatibilité.

### 2. Utilisez le helper dans vos vues

#### Upload simple (record existant)

```erb
<%= form_with model: @user do |f| %>
  <%= f.text_field :name %>

  <%= upload_field :avatar, record: @user %>

  <%= f.submit %>
<% end %>
```

#### Upload multiple avec configuration personnalisée

```erb
<%= upload_field :documents,
                 record: @project,
                 multiple: true,
                 accepted_types: '.pdf,.docx',
                 max_size: 10.megabytes %>
```

#### Upload temporaire (nouveau record)

Pour les formulaires de création, utilisez upload temporaire :

```erb
<%= form_with model: @user, url: users_path do |f| %>
  <%# Champ caché pour lier les uploads temporaires %>
  <%= upload_session_field %>

  <%= f.text_field :name %>

  <%# Pas de record, les fichiers seront stockés temporairement %>
  <%= upload_field :avatar, accepted_types: '.png,.jpg' %>

  <%= f.submit %>
<% end %>
```

Dans votre controller :

```ruby
class UsersController < ApplicationController
  include UploadDND::Controllers::Uploadable

  def create
    @user = User.new(user_params)

    # Lie les uploads temporaires (vérifie le session_id automatiquement)
    wire_temporary_uploads(@user)

    if @user.save
      # Les fichiers temporaires seront automatiquement attachés
      redirect_to @user, notice: 'Utilisateur créé avec succès'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name)
  end
end
```

**Sécurité** : `wire_temporary_uploads` vérifie que le `session_id` correspond à la session actuelle.
Le `temp_upload_session_id` utilise une variable d'instance privée (`@_temp_upload_session_id`).

**Persistance au rechargement** : les fichiers temporaires sont liés à la session. Si
l'utilisateur recharge la page (F5, restauration de brouillon, reconnexion), le
composant affiche à nouveau les fichiers déjà déposés — rien à faire côté app.

Si votre formulaire remplace la zone sans repasser par `upload_field` (Turbo Frame,
formulaire multi-étapes…), vous pouvez récupérer le HTML de la liste vous-même :

```
GET /upload_d_n_d/temporary_attachments?attribute_name=documents
```

Réponse : le partial `<div id="udnd_files_list_documents">…</div>`, limité aux fichiers
de la session courante. `400` sans `attribute_name` valide.

**Annulation du formulaire** : les fichiers déposés restent liés à la session jusqu'à
purge automatique (`temporary_files_retention`). Pour qu'ils ne réapparaissent pas
dans le formulaire suivant quand l'utilisateur annule, purgez-les explicitement :

```
DELETE /upload_d_n_d/temporary_attachments?attribute_name=documents   → 204
```

Par exemple depuis un bouton « Annuler » :

```js
fetch("/upload_d_n_d/temporary_attachments?attribute_name=documents", {
  method: "DELETE",
  headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
}).then(() => Turbo.visit(backUrl))
```

Scopé sur la session courante ; soumis à la policy `destroy?` si Pundit est activé.

### 3. Utilisation dans différents namespaces

UploadDND fonctionne de manière transparente dans **tous les namespaces** de votre application :

#### Namespace public

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include UploadDND::Uploadable

  uploadable :avatar,
             accept: [:jpg, :png],
             max_size: 5.megabytes,
             strict_mime_check: true
end
```

```erb
<!-- app/views/users/edit.html.erb -->
<%= upload_field :avatar, record: @user %>
```

#### Namespace Admin

```ruby
# app/models/admin/article.rb
module Admin
  class Article < ApplicationRecord
    include UploadDND::Uploadable

    uploadable :images,
               accept: [:jpg, :png],
               max_size: 10.megabytes,
               multiple: true,
               max_files: 10,
               strict_mime_check: true
  end
end
```

```erb
<!-- app/views/admin/articles/edit.html.erb -->
<%= upload_field :images,
                 record: @article,
                 multiple: true %>
```

#### Namespace Manager ou autre

```ruby
# app/models/manager/report.rb
module Manager
  class Report < ApplicationRecord
    include UploadDND::Uploadable

    uploadable :pdf_file,
               accept: [:pdf],
               max_size: 50.megabytes,
               strict_mime_check: true
  end
end
```

```erb
<!-- app/views/manager/reports/new.html.erb -->
<%= upload_field :pdf_file,
                 record: @report,
                 accepted_types: '.pdf',
                 max_size: 50.megabytes %>
```

**Comment ça fonctionne :**
- Le moteur UploadDND est monté sur `/upload_d_n_d` (indépendant des namespaces)
- Le helper `upload_field` est disponible dans toutes les vues
- Le concern `Uploadable` peut être inclus dans n'importe quel modèle
- Les autorisations sont gérées au niveau du modèle (Pundit/CanCanCan)

#### Suppression de fichiers : par le moteur (défaut) ou par vos routes

Depuis la v0.7, la suppression d'un fichier passe par défaut par le moteur
de la gem (`DELETE /upload_d_n_d/attachments/:id` + `record_gid`), comme
l'upload : **aucune route requise côté app**, quel que soit le routing du
record (imbriqué, singulier, namespacé). L'autorisation utilise la policy
Pundit du record (`update?`), avec fallback sur
`UploadDND::AttachmentPolicy#destroy?` si le modèle n'a pas de policy.

L'upload sur un record existant (`POST /upload_d_n_d/attachments`) vérifie
la policy générique (`UploadDNDAttachmentPolicy#create?`) **puis** la policy
du record (`update?`) si le modèle en a une — depuis la v0.7.2.

Pour brancher de la logique après suppression :

```ruby
UploadDND.configure do |config|
  config.on_file_removed = ->(record, attribute_name, user) {
    Rails.logger.info "File removed from #{record.class}##{record.id} (#{attribute_name}) by #{user&.id}"
  }
end
```

Le flux historique (suppression via la route membre `remove_file` de votre
app et le concern `Controllers::Uploadable`) reste disponible :

```ruby
UploadDND.configure do |config|
  config.delete_route = :host # défaut : :engine
end
```

Utilisez-le si vos actions `remove_file` contiennent de la logique custom
que `on_file_removed` ne couvre pas. Le reste de cette section ne concerne
que ce mode `:host`.

#### Records imbriqués ou resources singulières (mode `:host` uniquement)

En mode `:host`, la liste de fichiers construit l'URL de suppression via
`polymorphic_path(record)` : le record doit donc avoir une route
polymorphique. C'est automatique pour un `resources :xxx` top-level (y
compris namespacé), mais **pas** pour une resource imbriquée ou singulière.
Dans ce cas, déclarez la résolution dans `config/routes.rb` avec
[`resolve`](https://guides.rubyonrails.org/routing.html#using-resolve) — le
mécanisme Rails prévu pour ça :

```ruby
# resource :convention (singulière), imbriquée sous resources :projects
resolve("Convention") { |convention, options| route_for(:project_convention, convention.project, options) }

# resources :documents imbriqué sous resources :projects
resolve("Document") { |document, options| route_for(:project_document, document.project, document, options) }
```

> `resolve` se déclare au niveau racine du bloc `routes.draw`.

Sans résolution possible, la gem lève `UploadDND::UnroutableRecordError`
avec ces instructions (plutôt qu'un `undefined method 'xxx_path'` cryptique).

Pour un routing vraiment exotique, le point d'extension officiel est le
helper `udnd_remove_file_url(record, attachment, attribute_name)`, à
redéfinir dans le `ApplicationHelper` de votre app. **Ne shadowez pas le
partial `_files_list`** pour ça : un partial copié ne suit pas les mises à
jour de la gem.

### 4. Autorisation (optionnel)

#### Avec Pundit

```ruby
# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  def update?
    user == record || user.admin?
  end
end
```

#### Avec CanCanCan

```ruby
# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    can :update, User, id: user.id
  end
end
```

## Sécurité

UploadDND implémente plusieurs couches de sécurité :

1. **Validation content-type (allowlist)** : Vérifie que le type MIME du blob est autorisé (ex: `image/png`, `application/pdf`)
   - **Anti-spoofing (optionnel)** : si vous utilisez le `FileValidator`, activez `strict_mime_check: true` pour analyser le contenu réel du fichier via Marcel (plus coûteux car nécessite de lire le fichier côté serveur).
2. **Protection CSRF** : Tokens automatiques pour tous les uploads
3. **Validation de paramètres** : Empêche l'injection de paramètres malveillants
4. **Autorisation** : Support Pundit/CanCanCan
5. **Session isolation** : Les fichiers temporaires sont isolés par session
6. **Logging** : Audit trail complet de tous les uploads/suppressions
7. **Un fichier = un propriétaire** : un `signed_id` déjà rattaché (à un record ou à un fichier temporaire) est refusé (422). Le `signed_id` figure dans chaque URL de fichier : sans ce contrôle, un tiers pourrait rattacher le fichier d'un autre à ses propres records

Exemple (anti-spoofing activé) :

```ruby
uploadable :avatar,
           accept: [:jpg, :png],
           max_size: 5.megabytes,
           strict_mime_check: true
```

### Rate limiting

La gem embarque un rate limiting sur ses endpoints d'attachement
(`POST /upload_d_n_d/attachments` et `/upload_d_n_d/temporary_attachments`),
désactivé par défaut. Pour l'activer :

```ruby
UploadDND.configure do |config|
  config.rate_limit_enabled = true
  config.rate_limit_max_requests = 30   # par utilisateur+IP
  config.rate_limit_period = 60         # secondes
end
```

Dimensionnez `rate_limit_max_requests` en fonction de vos usages : un upload
multiple déclenche une requête d'attachement **par fichier**. Une limite trop
basse fera échouer les derniers fichiers d'un lot légitime (HTTP 429).

Le compteur s'appuie sur `Rails.cache` : en production, utilisez un store
partagé entre processus (Redis, Memcached, SolidCache) pour que la limite
soit globale et non par worker.

### ⚠️ Protéger l'endpoint DirectUpload

Les fichiers sont téléversés via ActiveStorage DirectUpload, c'est-à-dire par
`POST /rails/active_storage/direct_uploads` — une route de **votre
application**, hors du périmètre de la gem. Le rate limiting ci-dessus ne la
couvre pas : sans protection, un attaquant peut créer des blobs en masse et
saturer votre stockage sans jamais toucher les endpoints de la gem.

Protégez-la côté application, par exemple avec [rack-attack](https://github.com/rack/rack-attack) :

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("direct_uploads/ip", limit: 30, period: 1.minute) do |req|
  req.ip if req.path == "/rails/active_storage/direct_uploads" && req.post?
end
```

#### Fichiers refusés

Avec DirectUpload, le fichier est déjà dans votre stockage quand la gem le
contrôle. Quand elle le refuse (taille, type, validation du modèle, erreur à
l'enregistrement), elle le purge en arrière-plan
(`UploadDND::PurgeRejectedBlobJob`, file `active_storage.queues.purge`), avec
ces garde-fous :

- un fichier rattaché à un record ou à un fichier temporaire n'est jamais supprimé, ni au refus ni à l'exécution du job ;
- seul un fichier envoyé récemment est purgé (`config.rejected_blob_purge_window`, 1 heure par défaut ; `nil` désactive la purge) ;
- rien n'est supprimé si l'autorisation n'a pas été explicitement accordée (refus 401 ou 403, ou autorisation qui n'aboutit pas).

Pensez aussi au job de nettoyage des blobs orphelins (blobs créés par
DirectUpload mais jamais attachés) : `ActiveStorage::Blob.unattached` +
`purge_later` en tâche planifiée.

## Nettoyage automatique

La gem fournit `UploadDND::CleanupTemporaryAttachmentsJob`, qui purge les
fichiers temporaires expirés (au-delà de `temporary_files_retention` jours).
Aucun job à écrire côté app : il suffit de planifier sa récurrence.

Avec solid_queue (Rails 8+) :

```yaml
# config/recurring.yml
production:
  cleanup_temporary_uploads:
    class: UploadDND::CleanupTemporaryAttachmentsJob
    schedule: every day at 2am
    queue: background
```

Ou avec Mission Control - Jobs dans `config/initializers/solid_queue.rb` :

```ruby
# config/initializers/solid_queue.rb
SolidQueue.configure do |config|
  config.recurring_tasks = [
    {
      key: "cleanup_temporary_uploads",
      schedule: "0 2 * * *", # Tous les jours à 2h du matin (cron syntax)
      class: "UploadDND::CleanupTemporaryAttachmentsJob"
    }
  ]
end
```

Ou avec sidekiq-cron :

```yaml
# config/schedule.yml
cleanup_temporary_uploads:
  cron: "0 2 * * *"
  class: "UploadDND::CleanupTemporaryAttachmentsJob"
```

## Customisation du style

Surchargez les styles CSS en créant un fichier `app/assets/stylesheets/upload_d_n_d_custom.css` :

```css
.udnd-dropzone {
  border: 2px dashed var(--udnd-accent-color, #E97451);
  background: #f8f9fa;
}

.udnd-dropzone.dragover {
  background: #e9ecef;
  border-color: #28a745;
}
```

## Développement

Après avoir cloné le repo :

```bash
bundle install
rails db:migrate
rails server
```

Pour lancer les tests :

```bash
bundle exec rspec
```

## Roadmap

- [x] Prévisualisation (images + PDF) via Stimulus
- [x] Internationalisation (FR/EN) des messages serveur
- [x] Support complet des namespaces (Admin::, Manager::, etc.)
- [ ] Compression / optimisation d'images (optionnel, configurable)
- [ ] Scan antivirus (ClamAV ou service externe) avant attachement/persist
- [ ] Direct Upload (S3/GCS) + support des gros fichiers (UX + retry)
- [ ] Tests de générateurs (install + model) et amélioration de la couverture
- [ ] Internationalisation des messages côté JavaScript
- [ ] Guide "production hardening" (rate limiting, CSP, stockage, jobs cleanup)

## Contributing

Les contributions sont les bienvenues ! Merci de :
1. Forker le projet
2. Créer une branche pour votre feature (`git checkout -b feature/amazing-feature`)
3. Commiter vos changements (`git commit -m 'Add amazing feature'`)
4. Pusher vers la branche (`git push origin feature/amazing-feature`)
5. Ouvrir une Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
