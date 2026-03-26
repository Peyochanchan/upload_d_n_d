# frozen_string_literal: true

UploadDND::Engine.routes.draw do
  # Routes pour les attachments
  resources :attachments, only: [ :create, :destroy ]

  # Routes pour les attachments temporaires
  resources :temporary_attachments, only: [ :create, :destroy ]
end
