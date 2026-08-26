# frozen_string_literal: true

UploadDND::Engine.routes.draw do
  # Routes pour les attachments
  resources :attachments, only: [ :create, :destroy ]

  # Routes pour les attachments temporaires
  resources :temporary_attachments, only: [ :index, :create, :destroy ]
  # Purge de tous les fichiers temporaires de la session pour un attribut
  # (ex: bouton « Annuler » d'un formulaire de création)
  delete "temporary_attachments", to: "temporary_attachments#purge", as: :purge_temporary_attachments
end
