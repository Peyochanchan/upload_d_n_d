# frozen_string_literal: true

# Modèle de test sans namespace
class User < ActiveRecord::Base
  self.table_name = 'users'
  include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

  has_one_attached :avatar
  has_many_attached :documents
end

# Namespace Admin
module Admin
  class Article < ActiveRecord::Base
    self.table_name = 'admin_articles'
    include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

    has_many_attached :images
  end
end

# Namespace Manager
module Manager
  class Report < ActiveRecord::Base
    self.table_name = 'manager_reports'
    include UploadDND::Uploadable if defined?(UploadDND::Uploadable)

    has_one_attached :pdf_file
  end
end
