# Modèle de démonstration (navigateur) : limites par champ plus larges que la
# configuration globale de l'app dummy, comme dans une app hôte réelle.
class DemoProject < ApplicationRecord
  include UploadDND::Uploadable

  validates :name, presence: true

  uploadable :pictures, accept: [ :jpg, :jpeg, :png ], max_size: 2.megabytes, multiple: true
  uploadable :documents, accept: [ :pdf, :xlsx ], max_size: 20.megabytes, multiple: true
end
