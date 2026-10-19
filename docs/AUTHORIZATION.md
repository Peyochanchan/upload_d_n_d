# Guide d'autorisation UploadDND

Ce guide explique comment configurer l'authentification et l'autorisation pour la gem UploadDND.

## Table des matières

1. [Configuration de base](#configuration-de-base)
2. [Avec Pundit](#avec-pundit)
3. [Avec CanCanCan](#avec-cancancan)
4. [Sans librairie d'autorisation](#sans-librairie-dautorisation)
5. [Exemples complets](#exemples-complets)

---

## Configuration de base

### Authentification obligatoire

Par défaut, UploadDND requiert que les utilisateurs soient authentifiés pour uploader des fichiers.

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  # Exiger l'authentification (défaut: true)
  config.require_authentication = true
end
```

Si vous voulez permettre les uploads anonymes (non recommandé pour la production) :

```ruby
UploadDND.configure do |config|
  config.require_authentication = false
end
```

### Détection automatique du système d'autorisation

UploadDND détecte automatiquement si vous utilisez Pundit ou CanCanCan :

```ruby
# Détection automatique dans la configuration
config.authorization_adapter # => :pundit, :cancancan, ou nil
```

L'autorisation est **fail-closed** : sans adaptateur utilisable (`nil`, valeur
inconnue), tout upload et toute suppression sont refusés (403), et un
avertissement est journalisé au démarrage. Un adaptateur déclaré mais
inutilisable (`:pundit` sans `Pundit::Authorization` dans le contrôleur, par
exemple) fait échouer la requête (500). Pour se passer d'autorisation, il faut
le déclarer : `config.authorization_adapter = :none`.

---

## Avec Pundit

### Étape 1 : Générer la policy

```bash
rails generate upload_d_n_d:policy
```

Cela créera le fichier : `app/policies/upload_d_n_d_temporary_attachment_policy.rb`

### Étape 2 : Activer Pundit dans la configuration

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  config.authorization_adapter = :pundit
end
```

### Étape 3 : Personnaliser la policy

```ruby
# app/policies/upload_d_n_d_temporary_attachment_policy.rb
class UploadDNDTemporaryAttachmentPolicy < ApplicationPolicy
  def create?
    # Qui peut uploader des fichiers ?
    # Exemple : tous les utilisateurs connectés
    user.present?
  end

  def destroy?
    # Qui peut supprimer des fichiers ?
    user.present?
  end

  def cleanup?
    # Qui peut nettoyer les fichiers expirés ?
    # (utilisé par les tâches cron/sidekiq)
    user&.admin?
  end
end
```

### Exemples de policies selon les besoins

#### Tous les utilisateurs authentifiés

```ruby
def create?
  user.present?
end
```

#### Seulement les admins

```ruby
def create?
  user&.admin?
end
```

#### Admins ou éditeurs

```ruby
def create?
  user&.admin? || user&.editor?
end
```

#### Selon un rôle ou permission personnalisée

```ruby
def create?
  user&.can_upload_files? # méthode personnalisée sur User
end
```

#### Exemple complet (inspiré d'l'app hôte)

```ruby
class UploadDNDTemporaryAttachmentPolicy < ApplicationPolicy
  def create?
    user&.staff? || user&.editor?
  end

  def destroy?
    user&.staff? || user&.editor?
  end

  def cleanup?
    user&.staff? ||
      user&.editor? ||
      user&.team&.regional_team?
  end

  private

  # Méthode helper dans le modèle User
  # def staff?
  #   admin? || supervisor?
  # end
end
```

---

## Avec CanCanCan

### Étape 1 : Activer CanCanCan

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  config.authorization_adapter = :cancancan
end
```

### Étape 2 : Définir les abilities

Les sujets génériques sont des symboles. Sans règle, CanCanCan refuse : il
n'y a pas de repli comme avec Pundit, la règle `:update` du record est donc
exigée pour l'upload et la suppression sur un record existant.

| Action | Règle |
|---|---|
| Upload sur un record | `:create, :upload_d_n_d_attachment` puis `:update, record` |
| Suppression sur un record | `:update, record` |
| Upload temporaire | `:create, :upload_d_n_d_temporary_attachment` |
| Suppression temporaire, purge | `:destroy, :upload_d_n_d_temporary_attachment` |

```ruby
# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)

    can :create, :upload_d_n_d_attachment
    can :update, Document, user_id: user.id

    if user.admin?
      # Admins peuvent tout faire
      can :manage, :upload_d_n_d_temporary_attachment
    elsif user.editor?
      # Éditeurs peuvent créer et supprimer
      can [:create, :destroy], :upload_d_n_d_temporary_attachment
    else
      # Utilisateurs normaux peuvent seulement uploader
      can :create, :upload_d_n_d_temporary_attachment
    end
  end
end
```

---

## Sans librairie d'autorisation

Sans Pundit ni CanCanCan, la gem refuse tout tant que l'absence
d'autorisation n'est pas déclarée. Seule l'authentification est alors vérifiée
(`require_authentication`) : tout utilisateur connecté peut uploader et
supprimer sur n'importe quel record dont il connaît le GlobalID.

**⚠️ Non recommandé en production**

```ruby
# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  config.authorization_adapter = :none
end
```

---

## Exemples complets

### Exemple 1 : Application simple avec Devise + Pundit

```ruby
# Gemfile
gem 'devise'
gem 'pundit'
gem 'upload_d_n_d'

# config/initializers/upload_d_n_d.rb
UploadDND.configure do |config|
  config.require_authentication = true
  config.authorization_adapter = :pundit
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization
end

# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end
end

# app/policies/upload_d_n_d_temporary_attachment_policy.rb
class UploadDNDTemporaryAttachmentPolicy < ApplicationPolicy
  def create?
    user.present? # Tous les utilisateurs authentifiés
  end

  def destroy?
    user.present?
  end

  def cleanup?
    user&.admin? # Seulement les admins
  end
end
```

### Exemple 2 : Application avec rôles complexes (style l'app hôte)

```ruby
# app/models/user.rb
class User < ApplicationRecord
  enum role: {
    member: 0,
    contributor: 10,
    manager: 20,
    supervisor: 30,
    admin: 90
  }

  # Attribut boolean
  # editor: boolean

  def staff?
    admin? || supervisor?
  end
end

# app/policies/upload_d_n_d_temporary_attachment_policy.rb
class UploadDNDTemporaryAttachmentPolicy < ApplicationPolicy
  def create?
    user&.staff? || user&.editor?
  end

  def destroy?
    user&.staff? || user&.editor?
  end

  def cleanup?
    user&.staff? ||
      user&.editor? ||
      user&.team&.regional_team?
  end
end

# app/controllers/projects_controller.rb
class ProjectsController < ApplicationController
  include UploadDND::Uploadable

  def create
    @project = Project.new(project_params)

    if @project.save
      # Attache automatiquement les fichiers temporaires
      attach_upload_d_n_d_files(@project, :documents)

      redirect_to @project, notice: 'Projet créé'
    else
      render :new
    end
  end

  private

  def project_params
    params.require(:project).permit(:title, :description)
  end
end
```

### Exemple 3 : Tests RSpec pour la policy

```ruby
# spec/policies/upload_d_n_d_temporary_attachment_policy_spec.rb
require 'rails_helper'

RSpec.describe UploadDNDTemporaryAttachmentPolicy do
  subject { described_class.new(user, :upload_d_n_d_temporary_attachment) }

  context 'for an admin user' do
    let(:user) { create(:user, role: :admin) }

    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:destroy) }
    it { is_expected.to permit_action(:cleanup) }
  end

  context 'for an editor' do
    let(:user) { create(:user, editor: true) }

    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:destroy) }
  end

  context 'for a regular user' do
    let(:user) { create(:user, role: :member) }

    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
    it { is_expected.to forbid_action(:cleanup) }
  end

  context 'for a guest user (not logged in)' do
    let(:user) { nil }

    it { is_expected.to forbid_action(:create) }
    it { is_expected.to forbid_action(:destroy) }
    it { is_expected.to forbid_action(:cleanup) }
  end
end
```

---

## Utilisation du concern Uploadable

Le concern `UploadDND::Uploadable` fourni des méthodes utiles pour vos controllers :

### Attacher des fichiers temporaires à un record

```ruby
class ProjectsController < ApplicationController
  include UploadDND::Uploadable

  def create
    @project = Project.new(project_params)

    if @project.save
      # Attache tous les fichiers temporaires de l'attribut :documents
      attach_upload_d_n_d_files(@project, :documents)

      redirect_to @project
    else
      render :new
    end
  end
end
```

### Autoriser un record pour update (avec support namespace Pundit)

```ruby
class Admin::ProjectsController < ApplicationController
  include UploadDND::Uploadable

  def update
    @project = Project.find(params[:id])

    # Autorise avec namespace [:admin, @project]
    authorize_record_for_update(@project)

    if @project.update(project_params)
      redirect_to [:admin, @project]
    else
      render :edit
    end
  end
end
```

---

## Sécurité supplémentaire

### Validation du signed_blob_id

UploadDND valide automatiquement le format du `signed_blob_id` pour prévenir les injections :

- Longueur minimum de 20 caractères
- Format base64 uniquement (`[A-Za-z0-9\-_+=]`)
- Logging automatique des tentatives suspectes

### Sanitization des noms de fichiers

Tous les noms de fichiers sont automatiquement nettoyés :

- Suppression des caractères spéciaux
- Limitation à 255 caractères
- Préservation de l'extension

### Gestion des erreurs ActiveStorage

Le concern `Uploadable` gère automatiquement :

- `ActiveStorage::IntegrityError` (fichier corrompu)
- `ActiveStorage::UnrepresentableError` (fichier non traitable)

---

## Dépannage

### "Pundit::NotAuthorizedError"

Vérifiez que :
1. Vous avez généré la policy : `rails g upload_d_n_d:policy`
2. La policy retourne `true` pour `create?` ou `destroy?`
3. `config.authorization_adapter = :pundit` est bien configuré

### Tous les uploads sont refusés (403)

Aucun adaptateur utilisable : le log de démarrage indique `no usable
authorization adapter`. Déclarez `config.authorization_adapter` (`:pundit`,
`:cancancan` ou `:none`).

### "Vous devez être connecté"

Vérifiez que :
1. Devise (ou votre système d'auth) est bien configuré
2. `current_user` est disponible dans vos controllers
3. `config.require_authentication = true` si vous voulez forcer l'auth

### Les fichiers ne s'attachent pas

Vérifiez que :
1. Vous appelez `attach_upload_d_n_d_files(@record, :attribute_name)` après `save`
2. Le nom d'attribut correspond à celui du composant upload
3. L'utilisateur a bien la même session

---

## Ressources

- [Documentation Pundit](https://github.com/varvet/pundit)
- [Documentation CanCanCan](https://github.com/CanCanCommunity/cancancan)
- [Documentation Devise](https://github.com/heartcombo/devise)
