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
    before_action :validate_destroy_params, only: [ :destroy ]

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
        render_error(I18n.t("upload_d_n_d.errors.blob_not_found"), :not_found)
        return
      end

      unless record
        render_error(I18n.t("upload_d_n_d.errors.blob_not_found"), :not_found)
        return
      end

      # SÉCURITÉ : l'attribut doit être un attachment déclaré sur le modèle.
      # Détection SERVEUR du type d'attachment (has_one vs has_many) :
      # NE JAMAIS faire confiance au paramètre client params[:multiple]
      attachment = UploadDND::AttachmentLookup.find(record, attribute_name)
      unless attachment
        render_error(I18n.t("upload_d_n_d.errors.invalid_attribute", attribute: attribute_name), :unprocessable_entity)
        return
      end

      # Sanitize filename avant l'attachement
      @blob.update(filename: sanitize_filename(@blob.filename.to_s))

      if attachment.is_a?(ActiveStorage::Attached::Many)
        # has_many_attached: ajouter à la collection
        attachment.attach(@blob)
      elsif attachment.is_a?(ActiveStorage::Attached::One)
        # has_one_attached: remplacer (purge l'ancien automatiquement)
        record.send("#{attribute_name}=", @blob)
      else
        render_error(I18n.t("upload_d_n_d.errors.not_active_storage_attachment", attribute: attribute_name), :unprocessable_entity)
        return
      end

      # Sauvegarde avec validation
      if record.save
        render_file_list(record, attribute_name)
        log_upload_success
      else
        render_error(I18n.t("upload_d_n_d.errors.save_failed", errors: record.errors.full_messages.join(", ")), :unprocessable_entity)
      end
    rescue ActiveRecord::RecordInvalid => e
      render_error(I18n.t("upload_d_n_d.errors.save_failed", errors: e.message), :unprocessable_entity)
    end

    # DELETE /upload_d_n_d/attachments/:id
    #
    # Détache un fichier d'un record existant, sans dépendre des routes de
    # l'app hôte (contrairement au flux legacy remove_file du concern
    # Controllers::Uploadable). Symétrique du POST #create.
    #
    # Params:
    # - id: Integer (ActiveStorage::Attachment id)
    # - record_gid: String (GlobalID du record)
    # - attribute_name: String (ex: "avatar", "documents")
    def destroy
      record = GlobalID::Locator.locate(params[:record_gid])

      unless record
        render_error(I18n.t("upload_d_n_d.errors.record_not_found"), :not_found)
        return
      end

      authorize_destroy!(record)
      return if performed?

      attachment = ActiveStorage::Attachment.find_by(id: params[:id])
      attribute_name = params[:attribute_name]

      # Sécurité : le fichier doit appartenir au record ET à l'attribut annoncés
      if attachment && attachment.record == record && attachment.name == attribute_name.to_s
        attachment.purge_later
        record.reload

        UploadDND.configuration.on_file_removed&.call(record, attribute_name, current_user)

        render_file_list(record, attribute_name)
      else
        render_error(I18n.t("upload_d_n_d.errors.file_not_found_or_denied"), :not_found)
      end
    end

    private

    def validate_destroy_params
      unless params[:record_gid].present? && params[:attribute_name].present?
        render_error(I18n.t("upload_d_n_d.errors.missing_params"), :bad_request)
        return
      end

      unless params[:attribute_name].match?(/\A[a-z_][a-z0-9_]*\z/)
        render_error(I18n.t("upload_d_n_d.errors.invalid_attribute_name"), :bad_request)
        nil
      end
    end

    # Autorisation de la suppression : policy Pundit du record (update?),
    # avec fallback sur la policy générique de la gem si le modèle n'a pas
    # de policy. Fail-closed : sans policy du tout, Pundit::NotDefinedError
    # remonte en 500 plutôt que de laisser passer.
    def authorize_destroy!(record)
      return unless pundit_enabled?

      begin
        authorize record, :update?
      rescue Pundit::NotDefinedError
        authorize :upload_d_n_d_attachment, :destroy?
      end
    rescue Pundit::NotAuthorizedError
      render_error(I18n.t("upload_d_n_d.errors.unauthorized"), :forbidden)
    end

    def validate_record_gid_presence
      unless params[:record_gid].present?
        render_error(I18n.t("upload_d_n_d.errors.record_gid_required"), :bad_request)
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
          format.json { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_added") }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: I18n.t("upload_d_n_d.success.file_added") }
          format.any { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_added") }, status: :ok }
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
      render_error(I18n.t("upload_d_n_d.errors.unauthorized"), :forbidden)
    end
  end
end
