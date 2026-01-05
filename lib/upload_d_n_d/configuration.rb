# frozen_string_literal: true

module UploadDND
  class Configuration
    attr_accessor :max_size,
                  :accepted_types,
                  :main_color,
                  :allow_anonymous_uploads,
                  :require_authentication,
                  :temporary_files_retention,
                  :authorization_adapter,
                  :validator_class,
                  :active_storage_service,
                  :on_upload_success,
                  :on_upload_error,
                  :rate_limit_enabled,
                  :rate_limit_max_requests,
                  :rate_limit_period

    def initialize
      # Valeurs par défaut
      @max_size = 10.megabytes
      @accepted_types = '.pdf,.doc,.docx,.jpg,.jpeg,.png,.gif'
      @main_color = '#E97451'
      @allow_anonymous_uploads = false
      @require_authentication = true # Par défaut, authentification requise
      @temporary_files_retention = 7 # jours
      @authorization_adapter = detect_authorization_adapter
      @validator_class = 'FileValidator'
      @active_storage_service = nil # Utilise le service par défaut de Rails
      @on_upload_success = nil
      @on_upload_error = nil
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