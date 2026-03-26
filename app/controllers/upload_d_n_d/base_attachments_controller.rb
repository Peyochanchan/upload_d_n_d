# frozen_string_literal: true

module UploadDND
  # Contrôleur de base contenant toute la logique commune aux attachments
  # permanents et temporaires.
  #
  # Responsabilités:
  # - Validation des paramètres (signed_blob_id, attribute_name)
  # - Authentification et autorisation (Devise/Pundit)
  # - Gestion des erreurs et logging
  # - Helpers de rendu (Turbo Streams, JSON, HTML)
  # - Sécurité (CSRF, validation de signature, sanitisation)
  # - Rate limiting (contrôle du taux de requêtes)
  class BaseAttachmentsController < ActionController::Base
    # Inclure Pundit si disponible
    include Pundit::Authorization if defined?(Pundit)

    # Inclure le rate limiting
    include UploadDND::RateLimiting

    # Protection CSRF (désactivée uniquement en test)
    skip_before_action :verify_authenticity_token, if: -> { Rails.env.test? }

    # Authentification (si disponible dans l'app hôte)
    before_action :authenticate_user_if_available!

    # Gestion des erreurs
    # IMPORTANT: rescue_from utilise le "dernier match" -> on déclare StandardError en premier
    # pour laisser les handlers spécifiques (RecordNotFound, etc.) prendre le dessus.
    rescue_from StandardError, with: :handle_error
    rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
    rescue_from ActiveStorage::IntegrityError, with: :blob_integrity_error
    rescue_from ActionController::BadRequest, with: :bad_request_error

    before_action :validate_params, only: [ :create ]
    before_action :validate_signed_blob_id_format, only: [ :create ]
    before_action :find_blob, only: [ :create ]

    protected

    # === Callbacks de validation ===

    def validate_params
      unless params[:signed_blob_id].present? && params[:attribute_name].present?
        render_error(I18n.t("upload_d_n_d.errors.missing_params"), :bad_request)
        return
      end

      # Validation du nom d'attribut (alphanumeric + underscore uniquement)
      unless params[:attribute_name].match?(/\A[a-z_][a-z0-9_]*\z/)
        render_error(I18n.t("upload_d_n_d.errors.invalid_attribute_name"), :bad_request)
        nil
      end
    end

    def find_blob
      @blob = ActiveStorage::Blob.find_signed(params[:signed_blob_id])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      render_error(I18n.t("upload_d_n_d.errors.invalid_blob_signature"), :unauthorized)
      nil
    end

    # === Helpers de rendu ===

    def render_error(message, status = :unprocessable_entity)
      render json: { error: message }, status: status
    end

    def render_turbo_stream_replace(target, partial:, locals:)
      html = render_to_string(partial: partial, formats: [ :html ], locals: locals)
      turbo_stream_markup = %(<turbo-stream action="replace" target="#{ERB::Util.html_escape(target)}"><template>#{html}</template></turbo-stream>)

      render body: turbo_stream_markup, content_type: "text/vnd.turbo-stream.html"
    end

    # === Gestion des erreurs ===

    def record_not_found
      render_error(I18n.t("upload_d_n_d.errors.record_not_found"), :not_found)
    end

    def blob_integrity_error
      render_error(I18n.t("upload_d_n_d.errors.corrupted"), :unprocessable_entity)
    end

    def handle_error(exception)
      Rails.logger.error "UploadDND Error: #{exception.class} - #{exception.message}"
      Rails.logger.error exception.backtrace.join("\n")

      render_error(I18n.t("upload_d_n_d.errors.upload_error"), :internal_server_error)
    end

    def bad_request_error(exception)
      Rails.logger.warn "UploadDND BadRequest: #{exception.message}"
      render_error(exception.message, :bad_request)
    end

    # === Logging ===

    def log_upload_success
      return unless UploadDND.configuration.respond_to?(:on_upload_success)

      UploadDND.configuration.on_upload_success&.call(@blob, current_user)
    end

    # === Helpers d'authentification ===

    def current_user
      # Tente de récupérer current_user depuis l'application hôte
      # En utilisant warden (Devise)
      if defined?(Warden) && request.env["warden"]
        request.env["warden"].user
      elsif respond_to?(:super, true)
        super
      else
        nil
      end
    end

    def authenticate_user_if_available!
      # Si l'app hôte a Devise, on l'utilise
      if defined?(Devise) && respond_to?(:authenticate_user!, true)
        authenticate_user!
      # Sinon, on vérifie qu'un current_user existe si config l'exige
      elsif UploadDND.configuration.require_authentication
        unless current_user.present?
          render_error(I18n.t("upload_d_n_d.errors.authentication_required"), :unauthorized)
          nil
        end
      end
    end

    # === Helpers d'autorisation ===

    def pundit_enabled?
      defined?(Pundit) && UploadDND.configuration.authorization_adapter == :pundit
    end

    # === Helpers de session ===

    def current_session_id
      sid =
        if session.respond_to?(:id)
          session.id
        else
          session[:id] || session["id"]
        end

      sid.to_s
    end

    # === Validation de sécurité ===

    def validate_signed_blob_id_format
      signed_blob_id = params[:signed_blob_id]

      return if signed_blob_id.blank?

      # Vérifier le format du signed_blob_id
      unless signed_blob_id.is_a?(String) &&
             signed_blob_id.length > 20 &&
             signed_blob_id.match?(/\A[A-Za-z0-9\-_+=]+\z/)
        Rails.logger.warn "UploadDND: Invalid signed_blob_id format attempted"
        render_error(I18n.t("upload_d_n_d.errors.invalid_file_token"), :unauthorized)
        nil
      end
    end

    def sanitize_filename(filename)
      # Supprime les caractères dangereux du nom de fichier
      filename = filename.to_s.strip

      # Remplace les caractères dangereux
      filename = filename.gsub(/[^\w\.\-]/, "_")

      # Limite la longueur
      filename = filename.truncate(255, omission: "")

      # Assure qu'il reste une extension
      filename = "file#{File.extname(filename)}" if filename.blank?

      filename
    end

    # === Support Turbo Streams ===

    def turbo_stream_request?
      params[:format].to_s == "turbo_stream" ||
        request.headers["Accept"].to_s.include?("text/vnd.turbo-stream.html")
    end
  end
end
