# frozen_string_literal: true

module UploadDND
  module Controllers
    module Uploadable
      extend ActiveSupport::Concern

    included do
      # Gestion des erreurs ActiveStorage
      rescue_from ActiveStorage::IntegrityError do |_e|
        respond_to do |format|
          format.turbo_stream do
            flash[:alert] = I18n.t("upload_d_n_d.errors.corrupted")
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: I18n.t("upload_d_n_d.errors.corrupted") }, status: :unprocessable_entity }
        end
      end

      rescue_from ActiveStorage::UnrepresentableError do |_e|
        respond_to do |format|
          format.turbo_stream do
            flash[:alert] = I18n.t("upload_d_n_d.errors.unrepresentable")
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: I18n.t("upload_d_n_d.errors.unrepresentable") }, status: :unprocessable_entity }
        end
      end
    end

    # Transfère le session_id d'upload temporaire vers le record,
    # uniquement si le param correspond à la session courante (sécurité).
    #
    # @param record [ApplicationRecord] le record sur lequel wirer le session_id
    def wire_temporary_uploads(record)
      sid = params[:temp_upload_session_id]
      if sid.present? && sid == UploadDND::SessionId.for(session)
        record.temp_upload_session_id = sid
      end
    end

    # Attache un fichier à un record existant
    # Utilise les fichiers temporaires uploadés via UploadDND
    #
    # @param record [ApplicationRecord] le record sur lequel attacher
    # @param attribute_name [String, Symbol] le nom de l'attribut (ex: :avatar, :documents)
    def attach_upload_d_n_d_files(record, attribute_name)
      # Délègue au modèle TemporaryAttachment pour éviter la duplication
      UploadDND::TemporaryAttachment.attach_to_record(
        UploadDND::SessionId.for(session),
        record,
        { attribute_name.to_s => attribute_name }
      )
    end

    # Autorise un record pour update via UploadDND::Authorization
    # (fail-closed). Avec Pundit, la policy namespacée du controller est
    # essayée d'abord (Admin::RecordPolicy), puis la policy top-level.
    #
    # L'erreur native de la librairie (Pundit::NotAuthorizedError...) est
    # relancée telle quelle, pour les rescue_from de l'app.
    #
    # @param record [ApplicationRecord] le record à autoriser
    def authorize_record_for_update(record)
      UploadDND::Authorization.authorize!(self, record, :update, namespace: policy_namespace)
    rescue UploadDND::Authorization::Denied, UploadDND::Authorization::RuleMissing => e
      raise e.cause || e
    end

    # Action pour attacher un fichier à un record existant (appelée via route de l'app)
    # Route attendue : POST /:model_name/:id/attach_file
    def attach_file
      # Utilise l'instance variable définie par before_action (ex: @project)
      record = instance_variable_get("@#{controller_name.singularize}")

      # Si pas d'instance variable, cherche le record via GlobalID (support namespaces)
      unless record
        if params[:record_gid].present?
          record = GlobalID::Locator.locate(params[:record_gid])
        else
          # Fallback pour compatibilité (à déprécier)
          model_name = params[:model_name] || controller_name.singularize
          record = find_record_for_upload(model_name, params[:id])
        end
      end

      authorize_record_for_update(record)
      # Posé seulement si l'autorisation a réussi : sans lui, rien n'est purgé.
      authorized = true

      blob = ActiveStorage::Blob.find_signed(params[:signed_blob_id])
      attribute_name = params[:attribute_name]

      # SÉCURITÉ : un blob déjà rattaché (signed_id visible dans chaque URL de
      # fichier) n'est pas rattaché une seconde fois. Pas de purge : il
      # appartient à un autre record.
      if blob&.attachments&.exists?
        render_attach_file_error(I18n.t("upload_d_n_d.errors.blob_already_attached"))
        return
      end

      # SÉCURITÉ : attribute_name vient du client — seul un attachment déclaré
      # sur le modèle est résolu, jamais une méthode quelconque (destroy...).
      attachment = UploadDND::AttachmentLookup.find(record, attribute_name)
      unless attachment
        discard_rejected_upload_blob(blob, authorized)
        render_attach_file_error(I18n.t("upload_d_n_d.errors.invalid_attribute", attribute: attribute_name))
        return
      end

      attachment.attach(blob)

      if record.save
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = I18n.t("upload_d_n_d.success.file_added")
            render turbo_stream: [
              turbo_stream.replace(
                "udnd_files_list_#{attribute_name}",
                partial: "upload_d_n_d/shared/files_list",
                locals: { record: record.reload, attribute_name: attribute_name }
              ),
              turbo_stream.replace("flash_messages", partial: "shared/flashes")
            ]
          end
          format.json { render json: { status: "ok" }, status: :ok }
        end
      else
        discard_rejected_upload_blob(blob, authorized)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = I18n.t("upload_d_n_d.errors.save_failed", errors: record.errors.full_messages.join(", "))
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: record.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    rescue StandardError
      # Refus de droits ou autorisation non aboutie : authorized est nil,
      # rien n'est purgé. L'exception est toujours relancée.
      discard_rejected_upload_blob(blob, authorized)
      raise
    end

    # Action pour supprimer un fichier d'un record existant (appelée via route de l'app)
    # Route attendue : DELETE /:model_name/:id/remove_file
    def remove_file
      # Utilise l'instance variable définie par before_action (ex: @project)
      record = instance_variable_get("@#{controller_name.singularize}")

      # Si pas d'instance variable, cherche le record via GlobalID (support namespaces)
      unless record
        if params[:record_gid].present?
          record = GlobalID::Locator.locate(params[:record_gid])
        else
          # Fallback pour compatibilité (à déprécier)
          model_name = params[:model_name] || controller_name.singularize
          record = find_record_for_upload(model_name, params[:id])
        end
      end

      authorize_record_for_update(record)

      attachment = ActiveStorage::Attachment.find(params[:file_id])
      attribute_name = params[:attribute_name]

      # Vérification de sécurité : le fichier appartient bien au record
      if attachment.record == record && attachment.name == attribute_name.to_s
        attachment.purge_later
        record.reload

        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = I18n.t("upload_d_n_d.success.file_removed")
            render turbo_stream: [
              turbo_stream.replace(
                "udnd_files_list_#{attribute_name}",
                partial: "upload_d_n_d/shared/files_list",
                locals: { record: record, attribute_name: attribute_name }
              ),
              turbo_stream.replace("flash_messages", partial: "shared/flashes")
            ]
          end
          format.json { render json: { status: "ok" }, status: :ok }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = I18n.t("upload_d_n_d.errors.file_not_found_or_denied")
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: I18n.t("upload_d_n_d.errors.blob_not_found") }, status: :not_found }
        end
      end
    end

    private

    def render_attach_file_error(message)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = message
          render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes"), status: :unprocessable_entity
        end
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
    end

    # Blob envoyé par DirectUpload puis refusé : purgé sous les garde-fous de
    # UploadDND::RejectedBlob, et seulement si l'autorisation a réussi. Un échec
    # de la purge ne masque pas l'erreur d'origine.
    def discard_rejected_upload_blob(blob, authorized)
      return unless authorized

      UploadDND::RejectedBlob.discard(blob)
    rescue StandardError => e
      Rails.logger.error "UploadDND: rejected blob purge failed - #{e.class}: #{e.message}"
    end

    # Retourne le namespace du controller si présent
    # Ex: Admin::ProjectsController => "Admin"
    # Ex: Admin::Internal::ProjectsController => "Admin::Internal"
    def controller_namespace
      controller_class = self.class.name.to_s
      namespace_parts = controller_class.split("::")
      if namespace_parts.length > 1
        namespace_parts[0...-1].join("::")
      else
        nil
      end
    end

    # Namespace du controller en symboles : Admin::Internal -> [:admin, :internal]
    def policy_namespace
      controller_namespace&.underscore&.split("/")&.map(&:to_sym)
    end

    # @deprecated Utilisez GlobalID à la place (params[:record_gid])
    # Trouve le record pour l'upload
    # Supporte les namespaces (ex: "admin_article" -> Admin::Article)
    def find_record_for_upload(model_name, record_id)
      # Tente de détecter le namespace depuis le controller
      if (ns = controller_namespace)
        # Convertit "article" en "Admin::Article" si on est dans Admin::ArticlesController
        class_name = "#{ns}::#{model_name.classify}"
        begin
          model_class = class_name.constantize
          return model_class.find(record_id)
        rescue NameError
          # Fallback si le namespace ne contient pas ce modèle
        end
      end

      # Fallback standard (sans namespace)
      model_class = model_name.classify.constantize
      model_class.find(record_id)
    end
    end
  end
end
