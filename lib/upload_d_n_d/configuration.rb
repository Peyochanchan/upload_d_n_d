# frozen_string_literal: true

module UploadDND
  class Configuration
    attr_accessor :max_size,
                  :accepted_types,
                  :strict_mime_check,
                  :main_color,
                  :allow_anonymous_uploads,
                  :require_authentication,
                  :temporary_files_retention,
                  :rejected_blob_purge_window,
                  :authorization_adapter,
                  :validator_class,
                  :active_storage_service,
                  :on_upload_success,
                  :on_upload_error,
                  :on_file_removed,
                  :delete_route,
                  :rate_limit_enabled,
                  :rate_limit_max_requests,
                  :rate_limit_period

    def initialize
      # Valeurs par défaut
      @max_size = 10.megabytes
      @accepted_types = ".pdf,.doc,.docx,.jpg,.jpeg,.png,.gif"
      @strict_mime_check = false
      @main_color = "#E97451"
      @allow_anonymous_uploads = false
      @require_authentication = true # Par défaut, authentification requise
      @temporary_files_retention = 7 # jours
      # Un blob refusé n'est purgé que s'il a été créé dans cette fenêtre
      # (envoi en cours) : un blob plus ancien peut être cité dans un HTML
      # stocké. nil désactive la purge des blobs refusés.
      @rejected_blob_purge_window = 1.hour
      @authorization_adapter = detect_authorization_adapter
      @validator_class = "FileValidator"
      @active_storage_service = nil # Utilise le service par défaut de Rails
      @on_upload_success = nil
      @on_upload_error = nil
      @on_file_removed = nil
      # :engine (défaut) : la suppression passe par le moteur de la gem,
      #   aucune route requise côté app (symétrique de l'upload).
      # :host (legacy) : la suppression passe par la route membre remove_file
      #   de l'app (concern Controllers::Uploadable) — nécessite une route
      #   polymorphique pour le record (cf. README, "Records imbriqués").
      @delete_route = :engine
      @rate_limit_enabled = false
      @rate_limit_max_requests = 10
      @rate_limit_period = 60 # secondes
    end

    private

    # Détecte automatiquement l'adapter d'autorisation disponible
    def detect_authorization_adapter
      return :pundit if defined?(Pundit)
      return :cancancan if defined?(CanCanCan)
      nil
    end
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Reset de la configuration (utile pour les tests)
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
