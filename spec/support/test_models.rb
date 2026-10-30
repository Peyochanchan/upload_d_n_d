# frozen_string_literal: true

# Modèle de test sans namespace
class User < ActiveRecord::Base
  self.table_name = 'users'
  include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

  uploadable :avatar
  uploadable :documents, multiple: true

  # Attachment NON déclaré `uploadable` : sert à vérifier le refus (F3) — un
  # has_one_attached quelconque ne doit pas être ciblable par la gem.
  has_one_attached :internal_file
end

# Namespace Admin
module Admin
  class Article < ActiveRecord::Base
    self.table_name = 'admin_articles'
    include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

    uploadable :images, multiple: true
  end
end

# Namespace Manager
module Manager
  class Report < ActiveRecord::Base
    self.table_name = 'manager_reports'
    include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

    uploadable :pdf_file
  end
end

# Modèle de test avec limites par champ (uploadable), sur la table users
class LimitedUser < ActiveRecord::Base
  self.table_name = 'users'
  include UploadDND::Uploadable

  uploadable :avatar, accept: [ :png ], max_size: 10, strict_mime_check: false
  uploadable :documents, accept: [ :pdf, :jpg ], max_size: 2.kilobytes, multiple: true
  # Limites partielles : les types retombent sur la configuration globale
  uploadable :cover, max_size: 20
end
