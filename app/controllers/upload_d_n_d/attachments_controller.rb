# frozen_string_literal: true

module UploadDND
  # Contrôleur dédié à la gestion des attachments permanents (sur records existants).
  #
  # Responsabilités:
  # - Attacher des fichiers à des records ActiveRecord déjà persistés
  # - Valider que le record existe via GlobalID
  # - Gérer has_one vs has_many attachments
  # - Renvoyer la liste des fichiers pour mise à jour UI
  #
  # Utilisé par:
  # - POST /upload_d_n_d/attachments (lors de l'upload sur record existant)
  #
  # Workflow:
  # 1. User uploads file on edit form → record_gid present in params
  # 2. Controller locates record via GlobalID
  # 3. Attaches blob directly to record.attribute_name
  # 4. Saves record with validations
  # 5. Returns updated file list
  #
  # Note: Pour les formulaires SANS record (ex: new User), utilisez TemporaryAttachmentsController.
  class AttachmentsController < BaseAttachmentsController
    # Autorisation Pundit (si disponible)
    before_action :authorize_upload!, only: [ :create ]

    before_action :validate_record_gid_presence, only: [ :create ]

    # POST /upload_d_n_d/attachments
    #
    # Params:
    # - signed_blob_id: String (ActiveStorage signed blob ID)
    # - attribute_name: String (ex: "avatar", "documents")
    # - record_gid: String (GlobalID du record, ex: "gid://app/User/123")
    # - multiple: String ("true" ou "false", optionnel)
    #
    # Returns:
    # - Turbo Stream pour remplacer la liste de fichiers
    # - JSON {status: 'ok'} en mode API
    def create
      attribute_name = params[:attribute_name]

      begin
        record = GlobalID::Locator.locate(params[:record_gid])
      rescue ActiveRecord::RecordNotFound
        render_error(I18n.t('upload_d_n_d.errors.blob_not_found'), :not_found)
        return
      end

      unless record
        render_error(I18n.t('upload_d_n_d.errors.blob_not_found'), :not_found)
        return
      end

      # Vérification que l'attribut existe
      unless record.respond_to?(attribute_name)
        render_error(I18n.t('upload_d_n_d.errors.invalid_attribute', attribute: attribute_name), :unprocessable_entity)
        return
      end

      # Sanitize filename avant l'attachement
      @blob.update(filename: sanitize_filename(@blob.filename.to_s))

      # Détection SERVEUR du type d'attachment (has_one vs has_many)
      # NE JAMAIS faire confiance au paramètre client params[:multiple]
      attachment = record.send(attribute_name)

      if attachment.is_a?(ActiveStorage::Attached::Many)
        # has_many_attached: ajouter à la collection
        attachment.attach(@blob)
      elsif attachment.is_a?(ActiveStorage::Attached::One)
        # has_one_attached: remplacer (purge l'ancien automatiquement)
        record.send("#{attribute_name}=", @blob)
      else
        render_error(I18n.t('upload_d_n_d.errors.not_active_storage_attachment', attribute: attribute_name), :unprocessable_entity)
        return
      end

      # Sauvegarde avec validation
      if record.save
        render_file_list(record, attribute_name)
        log_upload_success
      else
        render_error(I18n.t('upload_d_n_d.errors.save_failed', errors: record.errors.full_messages.join(", ")), :unprocessable_entity)
      end
    rescue ActiveRecord::RecordInvalid => e
      render_error(I18n.t('upload_d_n_d.errors.save_failed', errors: e.message), :unprocessable_entity)
    end

    private

    def validate_record_gid_presence
      unless params[:record_gid].present?
        render_error(I18n.t('upload_d_n_d.errors.record_gid_required'), :bad_request)
        nil
      end
    end

    def render_file_list(record, attribute_name)
      if turbo_stream_request?
        render_turbo_stream_replace(
          "udnd_files_list_#{attribute_name}",
          partial: "upload_d_n_d/shared/files_list",
          locals: { record: record, attribute_name: attribute_name }
        )
      else
        respond_to do |format|
          format.json { render json: { status: "ok", message: I18n.t('upload_d_n_d.success.file_added') }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: I18n.t('upload_d_n_d.success.file_added') }
          format.any { render json: { status: "ok", message: I18n.t('upload_d_n_d.success.file_added') }, status: :ok }
        end
      end
    end

    # === Autorisation ===

    def authorize_upload!
      return unless pundit_enabled?

      # Note: Pour les attachments permanents, on pourrait autoriser sur le record lui-même
      # mais pour simplifier on garde la même policy que les temporaires
      authorize :upload_d_n_d_attachment, :create?
    rescue Pundit::NotAuthorizedError
      render_error(I18n.t('upload_d_n_d.errors.unauthorized'), :forbidden)
    end
  end
end
