# frozen_string_literal: true

module UploadDND
  # Contrôleur de base contenant toute la logique commune aux attachments
  # permanents et temporaires.
  #
  # Responsabilités:
  # - Validation des paramètres (signed_blob_id, attribute_name)
  # - Authentification et autorisation (Devise, UploadDND::Authorization)
  # - Gestion des erreurs et logging
  # - Helpers de rendu (Turbo Streams, JSON, HTML)
  # - Sécurité (CSRF, validation de signature, sanitisation)
  # - Rate limiting (contrôle du taux de requêtes)
  # Contrôleur parent configurable (config.parent_controller) : par défaut
  # ActionController::Base (isolé), ou "ApplicationController" pour hériter des
  # hooks d'authentification/autorisation/multi-tenant de l'app hôte (F6).
  class BaseAttachmentsController < UploadDND.configuration.parent_controller.constantize
    # Inclure Pundit si disponible
    include Pundit::Authorization if defined?(Pundit)

    # Le moteur fait sa propre autorisation (port adaptateur). Si l'app hôte
    # (parent_controller = "ApplicationController") a les after_action Pundit
    # classiques (verify_authorized / verify_policy_scoped), on les retire des
    # routes du moteur : sinon `index` (qui ne passe pas par Pundit) lèverait
    # après le rendu → DoubleRenderError. raise: false = sans effet si absents.
    if defined?(::Pundit)
      skip_after_action :verify_authorized, raise: false
      skip_after_action :verify_policy_scoped, raise: false
    end

    # Inclure le rate limiting
    include UploadDND::RateLimiting

    # Nom d'attribut autorisé (alphanumérique + underscore uniquement)
    ATTRIBUTE_NAME_FORMAT = /\A[a-z_][a-z0-9_]*\z/

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
    # find_target est enregistré par chaque sous-classe (actions distinctes) :
    # le re-déclarer ici puis dans une sous-classe écraserait ses conditions.

    # Déclaré après find_blob (@blob connu) et avant les before_action des
    # sous-classes (autorisation, contraintes), qu'il englobe.
    around_action :discard_blob_on_rejection, only: [ :create ]

    protected

    # === Purge des blobs refusés ===

    # Avec DirectUpload, le blob est déjà dans le bucket : s'il est refusé
    # (réponse en erreur ou exception, relancée), on le purge — sous les
    # garde-fous de UploadDND::RejectedBlob.
    def discard_blob_on_rejection
      yield
    rescue StandardError
      discard_rejected_blob
      raise
    else
      discard_rejected_blob if response.status >= 400
    end

    # Ne purge que si l'autorisation a été posée comme réussie
    # (grant_upload_authorization!) : une requête refusée faute de droits, ou
    # dont l'autorisation n'a pas abouti (exception, adaptateur inconnu), ne
    # modifie rien. Un échec de la purge ne masque pas l'erreur d'origine : il
    # est journalisé, le blob restera au nettoyage.
    def discard_rejected_blob
      return unless upload_authorized?

      UploadDND::RejectedBlob.discard(@blob)
    rescue StandardError => e
      Rails.logger.error "UploadDND: rejected blob purge failed - #{e.class}: #{e.message}"
    end

    # À appeler par chaque contrôle d'autorisation, une fois réussi.
    def grant_upload_authorization!
      @upload_authorized = true
    end

    def revoke_upload_authorization!
      @upload_authorized = false
    end

    def upload_authorized?
      @upload_authorized == true
    end

    # === Callbacks de validation ===

    # SÉCURITÉ : le signed_id vient du navigateur et figure dans chaque URL de
    # fichier. Un blob déjà rattaché (record ou fichier temporaire) n'est pas
    # rattaché une seconde fois : il serait partagé avec un autre record.
    # À déclarer dans les sous-classes après l'autorisation, avant toute écriture.
    def reject_attached_blob
      return unless @blob&.attachments&.exists?

      Rails.logger.warn "UploadDND: already attached blob #{@blob.id} refused"
      render_error(I18n.t("upload_d_n_d.errors.blob_already_attached"), :unprocessable_entity)
    end

    def validate_params
      return if params[:signed_blob_id].present? && params[:target].present?

      render_error(I18n.t("upload_d_n_d.errors.missing_params"), :bad_request)
      nil
    end

    def find_blob
      @blob = ActiveStorage::Blob.find_signed(params[:signed_blob_id])
      return if @blob

      # find_signed renvoie nil (sans lever) sur signature invalide ou blob
      # supprimé : sans cette garde, @blob nil provoquait un 500 plus bas.
      render_error(I18n.t("upload_d_n_d.errors.invalid_blob_signature"), :unauthorized)
      nil
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      render_error(I18n.t("upload_d_n_d.errors.invalid_blob_signature"), :unauthorized)
      nil
    end

    # Vérifie et décode la cible signée (remplace les record_gid/attribute_name
    # bruts du client). Toute cible absente ou invalide est refusée.
    def find_target
      @target = UploadDND::SignedTarget.verify(params[:target])
    rescue UploadDND::SignedTarget::Invalid
      render_error(I18n.t("upload_d_n_d.errors.invalid_field_reference"), :bad_request)
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

      # Si la réponse est déjà rendue (ex. un after_action qui lève après coup),
      # ne pas re-rendre : cela provoquerait un DoubleRenderError.
      return if performed?

      render_error(I18n.t("upload_d_n_d.errors.upload_error"), :internal_server_error)
    end

    # Le détail de l'exception reste dans les logs, jamais dans la réponse.
    def bad_request_error(exception)
      Rails.logger.warn "UploadDND BadRequest: #{exception.message}"
      render_error(I18n.t("upload_d_n_d.errors.bad_request"), :bad_request)
    end

    # === Logging ===

    def log_upload_success
      return unless UploadDND.configuration.respond_to?(:on_upload_success)

      UploadDND.configuration.on_upload_success&.call(@blob, current_user)
    end

    # === Helpers d'authentification ===

    # Public : l'app hôte vérifie souvent `respond_to?(:current_user)` (sans
    # include_all) dans ses before_action / pour alimenter Current.user ; une
    # méthode protected y répondrait faux. Priorité au `current_user` fourni par
    # le parent (parent_controller = "ApplicationController"), repli Warden sinon.
    # NB : `defined?(super)` teste la présence d'une méthode parente (et non
    # `respond_to?(:super)`, qui cherchait à tort une méthode nommée :super).
    public def current_user
      return super if defined?(super)
      return request.env["warden"].user if defined?(Warden) && request.env["warden"]

      nil
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

    # Délègue au port d'autorisation (UploadDND::Authorization) : lève
    # Denied, RuleMissing ou ConfigurationError. Fail-closed sans adaptateur.
    def authorize_with_adapter!(subject, action, namespace: nil)
      UploadDND::Authorization.authorize!(self, subject, action, namespace: namespace)
    end

    def render_forbidden
      render_error(I18n.t("upload_d_n_d.errors.unauthorized"), :forbidden)
    end

    # === Helpers de session ===

    def current_session_id
      UploadDND::SessionId.for(session)
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
