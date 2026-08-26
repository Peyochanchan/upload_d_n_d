# frozen_string_literal: true

module UploadDND
  # Contrôleur dédié à la gestion des attachments temporaires.
  #
  # Responsabilités:
  # - Créer des TemporaryAttachment pour les formulaires qui n'ont pas encore de record
  # - Supprimer des fichiers temporaires (avant soumission du formulaire)
  # - Renvoyer la liste des fichiers temporaires pour mise à jour UI
  #
  # Utilisé par:
  # - GET /upload_d_n_d/temporary_attachments?attribute_name=x (liste de la session courante)
  # - POST /upload_d_n_d/temporary_attachments (lors de l'upload)
  # - DELETE /upload_d_n_d/temporary_attachments/:id (suppression avant soumission)
  # - DELETE /upload_d_n_d/temporary_attachments?attribute_name=x (purge, ex: annulation du formulaire)
  #
  # Workflow:
  # 1. User upload file in form (no record yet) → create TemporaryAttachment
  # 2. User submit form → UsersController calls attach_upload_d_n_d_files helper
  # 3. Helper transfers temp files to real record and destroys TemporaryAttachment
  class TemporaryAttachmentsController < BaseAttachmentsController
    # Autorisation Pundit (si disponible)
    before_action :authorize_upload!, only: [ :create ]
    before_action :authorize_delete!, only: [ :destroy, :purge ]

    before_action :find_temp_attachment, only: [ :destroy ]
    before_action :validate_blob_constraints, only: [ :create ]

    # GET /upload_d_n_d/temporary_attachments?attribute_name=documents
    #
    # Renvoie le HTML du partial `temp_files_list` pour les fichiers temporaires
    # de la session courante (ex: restaurer la zone après un rechargement de page
    # sans repasser par le composant).
    #
    # Sécurité: pas d'autorisation Pundit — le scope par session_id est le filtre.
    # Un utilisateur ne peut voir que ses propres fichiers temporaires.
    def index
      attribute_name = params[:attribute_name].to_s
      return render_error(I18n.t("upload_d_n_d.errors.missing_params"), :bad_request) if attribute_name.blank?
      return render_error(I18n.t("upload_d_n_d.errors.invalid_attribute_name"), :bad_request) unless attribute_name.match?(ATTRIBUTE_NAME_FORMAT)

      files = TemporaryAttachment.for_session(current_session_id)
                                  .for_attribute(attribute_name)
                                  .with_blobs

      render partial: "upload_d_n_d/shared/temp_files_list",
             formats: [ :html ],
             locals: { files: files, attribute_name: attribute_name },
             layout: false
    end

    # POST /upload_d_n_d/temporary_attachments
    #
    # Params:
    # - signed_blob_id: String (ActiveStorage signed blob ID)
    # - attribute_name: String (ex: "avatar", "documents")
    #
    # Returns:
    # - Turbo Stream pour remplacer la liste de fichiers
    # - JSON {status: 'ok'} en mode API
    def create
      attribute_name = params[:attribute_name]

      # Sanitize filename avant de créer l'attachment
      @blob.update(filename: sanitize_filename(@blob.filename.to_s))

      # SÉCURITÉ : Pour les attributs au singulier (has_one_attached probable),
      # purger les fichiers temporaires existants avant d'en créer un nouveau
      # Convention Rails : avatar, cover, logo = singulier = has_one
      #                    documents, images, files = pluriel = has_many
      if attribute_name.to_s == attribute_name.to_s.singularize
        # Attribut au singulier → probablement has_one_attached
        # Purger les fichiers temporaires existants pour cette session + attribut
        TemporaryAttachment.for_session(current_session_id)
                           .for_attribute(attribute_name)
                           .destroy_all
      end

      temp_attachment = TemporaryAttachment.create!(
        session_id: current_session_id,
        attribute_name: attribute_name,
        user_id: current_user&.id
      )
      temp_attachment.blob.attach(@blob)

      render_temp_file_list(attribute_name)
      log_upload_success
    rescue ActiveRecord::RecordInvalid => e
      render_error(I18n.t("upload_d_n_d.errors.save_failed", errors: e.message), :unprocessable_entity)
    end

    # DELETE /upload_d_n_d/temporary_attachments/:id
    #
    # Supprime un fichier temporaire avant soumission du formulaire.
    #
    # Sécurité: On ne peut supprimer que les fichiers de sa propre session/user_id.
    def destroy
      attribute_name = @temp_attachment.attribute_name
      @temp_attachment.destroy

      render_temp_file_list(attribute_name)
      log_deletion
    end

    # DELETE /upload_d_n_d/temporary_attachments?attribute_name=documents
    #
    # Purge tous les fichiers temporaires de la session courante pour cet attribut.
    # Typiquement appelé par le bouton « Annuler » d'un formulaire de création,
    # pour que les fichiers déposés ne réapparaissent pas au prochain formulaire.
    #
    # Sécurité: scopé sur la session courante uniquement. Renvoie 204.
    def purge
      attribute_name = params[:attribute_name].to_s
      return render_error(I18n.t("upload_d_n_d.errors.missing_params"), :bad_request) if attribute_name.blank?
      return render_error(I18n.t("upload_d_n_d.errors.invalid_attribute_name"), :bad_request) unless attribute_name.match?(ATTRIBUTE_NAME_FORMAT)

      purged = TemporaryAttachment.for_session(current_session_id)
                                   .for_attribute(attribute_name)
                                   .destroy_all

      Rails.logger.info "UploadDND: #{purged.size} temporary file(s) purged - #{attribute_name} by #{current_user&.id || 'anonymous'}"
      head :no_content
    end

    private

    def find_temp_attachment
      # Sécurité: on ne peut supprimer que les fichiers de sa propre session ou utilisateur
      scope = TemporaryAttachment.where(session_id: current_session_id)
      scope = scope.or(TemporaryAttachment.where(user_id: current_user&.id)) if current_user

      @temp_attachment = scope.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_error(I18n.t("upload_d_n_d.errors.file_not_found_or_denied"), :not_found)
    end

    def render_temp_file_list(attribute_name)
      files = TemporaryAttachment.for_session(current_session_id)
                                  .for_attribute(attribute_name)
                                  .with_blobs

      if turbo_stream_request?
        render_turbo_stream_replace(
          "udnd_files_list_#{attribute_name}",
          partial: "upload_d_n_d/shared/temp_files_list",
          locals: { files: files, attribute_name: attribute_name }
        )
      else
        respond_to do |format|
          format.json { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_uploaded") }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: I18n.t("upload_d_n_d.success.file_added") }
          format.any { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_uploaded") }, status: :ok }
        end
      end
    end

    def log_deletion
      Rails.logger.info "UploadDND: Temporary file deleted - #{@temp_attachment.attribute_name} by #{current_user&.id || 'anonymous'}"
    end

    def validate_blob_constraints
      return unless @blob

      max_size = UploadDND.configuration.max_size
      if max_size.present? && @blob.byte_size > max_size
        render_error(
          I18n.t(
            "upload_d_n_d.errors.too_large",
            max_size: ActiveSupport::NumberHelper.number_to_human_size(max_size)
          ),
          :unprocessable_entity
        )
        return
      end

      accepted_types = normalized_accepted_types
      if accepted_types.present? && !accepted_types.include?(@blob.content_type)
        render_error(
          I18n.t(
            "upload_d_n_d.errors.invalid_type",
            types: UploadDND.configuration.accepted_types
          ),
          :unprocessable_entity
        )
        return
      end

      return unless UploadDND.configuration.strict_mime_check
      return if accepted_types.blank?

      detected_content_type = Marcel::MimeType.for(
        @blob.download,
        name: @blob.filename.to_s
      )

      if detected_content_type.present? && !accepted_types.include?(detected_content_type)
        render_error(
          I18n.t(
            "upload_d_n_d.errors.invalid_type",
            types: UploadDND.configuration.accepted_types
          ),
          :unprocessable_entity
        )
        return
      end

      if detected_content_type.present? && detected_content_type != @blob.content_type
        render_error(
          I18n.t("upload_d_n_d.errors.suspicious_type"),
          :unprocessable_entity
        )
        nil
      end
    rescue StandardError => e
      render_error(
        I18n.t("upload_d_n_d.errors.mime_detection_failed", message: e.message),
        :unprocessable_entity
      )
    end

    def normalized_accepted_types
      raw = Array(UploadDND.configuration.accepted_types).flat_map { |value| value.to_s.split(",") }
      raw = raw.map(&:strip).reject(&:blank?)
      return [] if raw.empty?

      raw.filter_map do |type|
        if type.include?("/")
          type
        else
          ext = type.start_with?(".") ? type : ".#{type}"
          Marcel::MimeType.for(name: "file#{ext}")
        end
      end.uniq
    end

    # === Autorisation ===

    def authorize_upload!
      return unless pundit_enabled?

      authorize :upload_d_n_d_temporary_attachment, :create?
    rescue Pundit::NotAuthorizedError
      render_error(I18n.t("upload_d_n_d.errors.unauthorized"), :forbidden)
    end

    def authorize_delete!
      return unless pundit_enabled?

      authorize :upload_d_n_d_temporary_attachment, :destroy?
    rescue Pundit::NotAuthorizedError
      render_error(I18n.t("upload_d_n_d.errors.unauthorized"), :forbidden)
    end
  end
end
