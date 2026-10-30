# frozen_string_literal: true

module UploadDND
  # Contrôleur des attachments permanents (sur records existants).
  #
  # La cible (modèle, attribut, record, namespace de policy) provient d'un jeton
  # signé (`UploadDND::SignedTarget`) émis par le composant : le client ne
  # désigne plus le record ni l'attribut en clair. L'autorisation porte sur le
  # record (`:update`), avec le namespace du jeton, en fail-closed.
  #
  # Routes :
  # - POST /upload_d_n_d/attachments
  # - DELETE /upload_d_n_d/attachments/:id
  class AttachmentsController < BaseAttachmentsController
    before_action :find_target, only: [ :create, :destroy ]
    before_action :authorize_target!, only: [ :create, :destroy ]
    before_action :reject_attached_blob, only: [ :create ]

    # POST /upload_d_n_d/attachments
    #
    # Params : signed_blob_id, target (jeton signé).
    def create
      record = @target_record
      attribute_name = @target.attribute

      # L'attribut du jeton est déjà vérifié `uploadable` ; on résout l'objet
      # d'association (has_one vs has_many) par réflexion, jamais par le client.
      attachment = UploadDND::AttachmentLookup.find(record, attribute_name)
      unless attachment
        render_error(I18n.t("upload_d_n_d.errors.invalid_attribute", attribute: attribute_name), :unprocessable_entity)
        return
      end

      if (violation = @target.constraints.violation(@blob))
        render_error(@target.constraints.error_message(violation), :unprocessable_entity)
        return
      end

      @blob.update(filename: sanitize_filename(@blob.filename.to_s))

      if attachment.is_a?(ActiveStorage::Attached::Many)
        attachment.attach(@blob)
      elsif attachment.is_a?(ActiveStorage::Attached::One)
        record.send("#{attribute_name}=", @blob)
      else
        render_error(I18n.t("upload_d_n_d.errors.not_active_storage_attachment", attribute: attribute_name), :unprocessable_entity)
        return
      end

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
    # Params : id (ActiveStorage::Attachment), target (jeton signé).
    def destroy
      record = @target_record
      attribute_name = @target.attribute

      attachment = ActiveStorage::Attachment.find_by(id: params[:id])

      # Sécurité : le fichier doit appartenir au record ET à l'attribut signés.
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

    # Autorisation sur le record désigné par le jeton signé : policy `:update`,
    # avec le namespace du jeton (ex. Admin::RecordPolicy). Fail-closed : sans
    # policy utilisable (ni namespacée ni top-level), la requête est refusée
    # (403), avec un avertissement en log nommant la policy manquante.
    def authorize_target!
      @target_record = @target.record
      unless @target_record
        render_error(I18n.t("upload_d_n_d.errors.record_not_found"), :not_found)
        return
      end

      authorize_with_adapter!(@target_record, :update, namespace: @target.namespace)
      grant_upload_authorization!
    rescue ActiveRecord::RecordNotFound
      render_error(I18n.t("upload_d_n_d.errors.record_not_found"), :not_found)
    rescue UploadDND::Authorization::RuleMissing
      Rails.logger.warn "UploadDND: aucune policy d'autorisation pour " \
                        "#{@target.model_class} (namespace: #{@target.namespace.inspect}) - refus (fail-closed)"
      render_forbidden
    rescue UploadDND::Authorization::Denied
      render_forbidden
    end

    def render_file_list(record, attribute_name)
      if turbo_stream_request?
        render_turbo_stream_replace(
          "udnd_files_list_#{attribute_name}",
          partial: "upload_d_n_d/shared/files_list",
          locals: { record: record, attribute_name: attribute_name, namespace: @target.namespace }
        )
      else
        respond_to do |format|
          format.json { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_added") }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: I18n.t("upload_d_n_d.success.file_added") }
          format.any { render json: { status: "ok", message: I18n.t("upload_d_n_d.success.file_added") }, status: :ok }
        end
      end
    end
  end
end
