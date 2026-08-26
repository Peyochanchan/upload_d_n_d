# frozen_string_literal: true

require "upload_d_n_d/version"
require "upload_d_n_d/engine"
require "upload_d_n_d/configuration"
require "upload_d_n_d/session_id"
require "upload_d_n_d/file_validator"
require "upload_d_n_d/mime_types"
require "upload_d_n_d/uploadable"
require "upload_d_n_d/controllers/uploadable"

module UploadDND
  class Error < StandardError; end

  # Levée quand un record affiché dans la liste de fichiers n'a pas de route
  # polymorphique (resource imbriquée, singulière, ou non routée).
  # Remède côté app : resolve() dans config/routes.rb, ou surcharge du helper
  # udnd_remove_file_url. Voir README, section "Records imbriqués".
  class UnroutableRecordError < Error; end

  # Autoload des concerns, helpers et autres composants
  # Ces fichiers seront chargés automatiquement par le moteur Rails

  # Helpers publics pour les routes de la gem
  class << self
    # Retourne le path pour créer un attachement
    # @return [String] le chemin vers la création d'attachement
    def attachments_path
      Engine.routes.url_helpers.attachments_path
    end

    # Retourne le path pour un attachement spécifique
    # @param id [Integer, String] l'ID de l'attachement
    # @param options [Hash] options supplémentaires (ex: record_gid)
    # @return [String] le chemin vers l'attachement
    def attachment_path(id, **options)
      Engine.routes.url_helpers.attachment_path(id, **options)
    end

    # Retourne le path pour créer un attachement temporaire
    # @return [String] le chemin vers la création d'attachement temporaire
    def temporary_attachments_path
      Engine.routes.url_helpers.temporary_attachments_path
    end

    # Retourne le path pour un attachement temporaire spécifique
    # @param id [Integer, String] l'ID de l'attachement temporaire
    # @return [String] le chemin vers l'attachement temporaire
    def temporary_attachment_path(id)
      Engine.routes.url_helpers.temporary_attachment_path(id)
    end
  end
end
