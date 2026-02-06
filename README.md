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
- Copier les contrôleurs Stimulus dans `app/javascript/controllers/upload_d_n_d/`
  puis vous inviter à exécuter `bin/rails stimulus:manifest:update` (si votre manifest est auto-généré)
- Copier les styles dans `app/assets/stylesheets/upload_d_n_d.css` (**sans** modifier votre stylesheet principal)
- Installer le helper et le fichier d'autorisation (personnalisables)
- Servir les vues directement depuis la gem (aucune vue copiée dans l'app hôte)
- Monter les routes du moteur
- Créer le fichier de configuration
- (Optionnel) Générer la policy Pundit si Pundit est détecté

> **Architecture v0.4.0** : Les modules critiques (`Uploadable`, `Controllers::Uploadable`, `FileValidator`) sont fournis par le runtime de la gem. Ne créez pas de copies locales.

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

Exemple (anti-spoofing activé) :

```ruby
uploadable :avatar,
           accept: [:jpg, :png],
           max_size: 5.megabytes,
           strict_mime_check: true
```

## Nettoyage automatique

Ajoutez un job pour nettoyer les fichiers temporaires expirés :

```ruby
# app/jobs/cleanup_temporary_attachments_job.rb
class CleanupTemporaryAttachmentsJob < ApplicationJob
  queue_as :default

  def perform
    UploadDND::TemporaryAttachment.cleanup_expired!
  end
end
```

Planifiez-le avec solid_queue (Rails 8+) :

```ruby
# config/recurring.yml
production:
  cleanup_temporary_uploads:
    class: CleanupTemporaryAttachmentsJob
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
      class: "CleanupTemporaryAttachmentsJob"
    }
  ]
end
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
