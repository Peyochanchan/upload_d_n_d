# Exemples d'utilisation du générateur UploadDND

## Ce que fait le générateur (non-invasif)

Quand vous exécutez `rails g upload_d_n_d:model`, le générateur :

✅ Affiche les snippets à copier/coller pour :
  - le modèle (`include UploadDND::Uploadable`, `has_*_attached`, `uploadable`)
  - le controller (`include UploadDND::Controllers::Uploadable`, before_action, create)
  - les routes (`member { post :attach_file; delete :remove_file }`)
✅ Génère des fichiers uniquement s'ils n'existent pas déjà (ex: controller/vues)

Vous devez copier/coller les snippets dans les fichiers concernés (le générateur ne modifie pas vos fichiers existants).

---

## Scénario 1 : Avatar utilisateur simple

```bash
# 1. Créer le modèle User
rails g model User name:string email:string

# 2. Configurer l'upload d'avatar
rails g upload_d_n_d:model User --attribute=avatar

# 3. Migrer
rails db:migrate
```

**Ce qui a été généré :**

`app/models/user.rb` :
```ruby
class User < ApplicationRecord
  include UploadDND::Uploadable

  has_one_attached :avatar

  uploadable :avatar,
             content_type: ["image/png", "image/jpeg"],
             max_size: 5.megabytes
end
```

`app/controllers/users_controller.rb` :
```ruby
class UsersController < ApplicationController
  include UploadDND::Controllers::Uploadable

  before_action :set_user, only: [:show, :edit, :update, :destroy, :attach_file, :remove_file]

  def create
    @user = User.new(user_params)
    @user.temp_upload_session_id = params[:temp_upload_session_id] if params[:temp_upload_session_id] == session.id.to_s

    if @user.save
      redirect_to @user, notice: 'User créé avec succès'
    else
      render :new, status: :unprocessable_entity
    end
  end
  # ...
end
```

`config/routes.rb` :
```ruby
Rails.application.routes.draw do
  resources :users do
    member do
      post :attach_file
      delete :remove_file
    end
  end
end
```

`app/views/users/_form.html.erb` :
```erb
<%= form_with model: @user do |f| %>
  <%= f.label :name %>
  <%= f.text_field :name %>

  <%= f.label :avatar %>
  <% if @user.persisted? %>
    <%= upload_field :avatar, record: @user %>
  <% else %>
    <%= upload_field :avatar %>
    <%= hidden_field_tag :temp_upload_session_id, session.id.to_s %>
  <% end %>

  <%= f.submit %>
<% end %>
```

---

## Scénario 2 : Galerie de photos pour produits

```bash
# 1. Créer le modèle Product
rails g model Product name:string price:decimal description:text

# 2. Configurer l'upload multiple de photos (max 10)
rails g upload_d_n_d:model Product \
  --attribute=photos \
  --multiple \
  --max_files=10 \
  --content_type=png jpg webp

# 3. Migrer
rails db:migrate
```

**Résultat :**

`app/models/product.rb` :
```ruby
class Product < ApplicationRecord
  include UploadDND::Uploadable

  has_many_attached :photos

  uploadable :photos,
             content_type: ["image/png", "image/jpeg", "image/webp"],
             max_size: 5.megabytes,
             max_files: 10
end
```

**Utilisation dans les vues :**
```erb
<%= upload_field :photos, record: @product, multiple: true %>
```

---

## Scénario 3 : Documents dans un namespace Admin

```bash
# 1. Créer le modèle namespacé
rails g model Admin::Article title:string content:text published:boolean

# 2. Configurer l'upload de documents PDF
rails g upload_d_n_d:model Admin::Article \
  --attribute=documents \
  --multiple \
  --content_type=pdf \
  --max_size=20

# 3. Migrer
rails db:migrate
```

**Résultat :**

`app/models/admin/article.rb` :
```ruby
module Admin
  class Article < ApplicationRecord
    include UploadDND::Uploadable

    has_many_attached :documents

    uploadable :documents,
               content_type: ["application/pdf"],
               max_size: 20.megabytes
  end
end
```

`app/controllers/admin/articles_controller.rb` :
```ruby
module Admin
  class ArticlesController < ApplicationController
    def create
      @article = Article.new(article_params)
      @article.temp_upload_session_id = params[:temp_upload_session_id] if params[:temp_upload_session_id] == session.id.to_s

      if @article.save
        redirect_to @article, notice: 'Admin::Article créé avec succès'
      else
        render :new, status: :unprocessable_entity
      end
    end
    # ...
  end
end
```

**Routes :**
```ruby
namespace :admin do
  resources :articles
end
```

---

## Scénario 4 : Rapport Manager avec PDF unique

```bash
# 1. Créer le modèle namespacé
rails g model Manager::Report title:string generated_at:datetime

# 2. Configurer l'upload d'un seul PDF
rails g upload_d_n_d:model Manager::Report \
  --attribute=pdf_file \
  --content_type=pdf \
  --max_size=50

# 3. Migrer
rails db:migrate
```

**Résultat :**

`app/models/manager/report.rb` :
```ruby
module Manager
  class Report < ApplicationRecord
    include UploadDND::Uploadable

    has_one_attached :pdf_file

    uploadable :pdf_file,
               content_type: ["application/pdf"],
               max_size: 50.megabytes
  end
end
```

---

## Scénario 5 : Fichiers multiples avec types variés

```bash
# Documents Word, Excel, PDF
rails g upload_d_n_d:model Project \
  --attribute=attachments \
  --multiple \
  --content_type=pdf doc docx xls xlsx \
  --max_size=15 \
  --max_files=20
```

**Résultat :**
```ruby
class Project < ApplicationRecord
  include UploadDND::Uploadable

  has_many_attached :attachments

  uploadable :attachments,
             content_type: [
               "application/pdf",
               "application/msword",
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
               "application/vnd.ms-excel"
             ],
             max_size: 15.megabytes,
             max_files: 20
end
```

---

---

## Scénario 6 : Ajouter plusieurs attributs uploadables au même modèle

Si vous avez déjà configuré un attribut uploadable et que vous voulez en ajouter un autre, relancez le générateur pour obtenir le snippet du nouvel attribut :

```bash
# 1. Premier attribut
rails g upload_d_n_d:model Project --attribute=main_picture --content_type=jpg png

# 2. Deuxième attribut sur le MÊME modèle
rails g upload_d_n_d:model Project --attribute=photos --multiple --content_type=jpg png webp
```

**Le générateur affichera :**

✅ Le snippet du nouvel attribut uploadable → `uploadable :photos`
✅ Le snippet de l'association ActiveStorage → `has_many_attached :photos`
✅ Le snippet de la section d’affichage (à ajouter dans votre vue / partial d’affichage)

**Résultat dans le modèle :**
```ruby
class Project < ApplicationRecord
  include UploadDND::Uploadable

  has_one_attached :main_picture
  uploadable :main_picture,
             content_type: ["image/jpeg", "image/png"],
             max_size: 5.megabytes

  has_many_attached :photos
  uploadable :photos,
             content_type: ["image/jpeg", "image/png", "image/webp"],
             max_size: 5.megabytes
end
```

**Exemple de section d’affichage :**
```erb
<div class="uploads-section">
  <h3>Main picture</h3>
  <!-- Code pour afficher main_picture -->
</div>

<div class="uploads-section">
  <h3>Photos</h3>
  <!-- Code pour afficher photos -->
</div>
```

---

## Extensions de fichiers supportées

Le générateur accepte les **extensions de fichiers** au lieu des MIME types pour plus de simplicité.
Les extensions sont automatiquement converties en MIME types corrects.

### Extensions par catégorie

**Images** : `jpg`, `jpeg`, `png`, `gif`, `webp`, `svg`, `bmp`, `ico`, `tiff`

**Documents** : `pdf`, `doc`, `docx`, `xls`, `xlsx`, `ppt`, `pptx`, `odt`, `ods`, `odp`

**Texte** : `txt`, `csv`, `html`, `xml`, `json`, `md`

**Archives** : `zip`, `rar`, `7z`, `tar`, `gz`

**Audio** : `mp3`, `wav`, `ogg`, `flac`, `m4a`

**Vidéo** : `mp4`, `avi`, `mov`, `wmv`, `webm`, `mkv`

### Exemples d'utilisation

```bash
# Images uniquement
--content_type=jpg png gif

# Documents Office
--content_type=pdf doc docx xls xlsx

# Audio et vidéo
--content_type=mp3 wav mp4 mov

# Vous pouvez aussi utiliser les MIME types si vous préférez
--content_type=image/jpeg image/png
```

Le générateur affichera un résumé avec les extensions ET les MIME types convertis :

```
📋 Résumé:
  Extensions: jpg, png, pdf
  MIME types: image/jpeg, image/png, application/pdf
```

---

## Options avancées

### Sans générer le controller

Utile si vous avez déjà un controller personnalisé :

```bash
rails g upload_d_n_d:model User --attribute=avatar --no-controller
```

### Sans générer les vues

Utile si vous gérez vos vues différemment :

```bash
rails g upload_d_n_d:model User --attribute=avatar --no-views
```

### Combinaison

```bash
rails g upload_d_n_d:model User --attribute=avatar --no-controller --no-views
```

Cette commande ajoutera seulement le concern et l'association au modèle.

---

## Workflow complet : de zéro à héros

```bash
# 1. Installer la gem
bundle add upload_d_n_d

# 2. Installer les dépendances
rails g upload_d_n_d:install

# (si Stimulus est utilisé avec manifest auto-généré)
bin/rails stimulus:manifest:update
rails db:migrate

# 3. Créer un modèle
rails g model User name:string email:string
rails db:migrate

# 4. Configurer l'upload
rails g upload_d_n_d:model User --attribute=avatar

# 5. Lancer le serveur
rails s

# 6. Visiter http://localhost:3000/users/new
# ✨ Votre drag & drop est prêt!
```

---

## Debugging

### Voir ce qui sera généré sans exécuter

```bash
rails g upload_d_n_d:model User --attribute=avatar --pretend
```

### Aide

```bash
rails g upload_d_n_d:model --help
```

### Vérifier les fichiers générés

```bash
# Modèle
cat app/models/user.rb

# Controller
cat app/controllers/users_controller.rb

# Vues
cat app/views/users/_form.html.erb
# (selon votre app, le rendu d’affichage peut être dans show.html.erb, un partial, etc.)
```
