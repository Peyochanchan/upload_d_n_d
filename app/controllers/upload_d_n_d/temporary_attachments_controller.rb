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
  # - POST /upload_d_n_d/temporary_attachments (lors de l'upload)
  # - DELETE /upload_d_n_d/temporary_attachments/:id (suppression avant soumission)
  #
  # Workflow:
  # 1. User upload file in form (no record yet) → create TemporaryAttachment
  # 2. User submit form → UsersController calls attach_upload_d_n_d_files helper
  # 3. Helper transfers temp files to real record and destroys TemporaryAttachment
  class TemporaryAttachmentsController < BaseAttachmentsController
    # Autorisation Pundit (si disponible)
    before_action :authorize_upload!, only: [:create]
    before_action :authorize_delete!, only: [:destroy]

    before_action :find_temp_attachment, only: [:destroy]

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
      render_error("Validation échouée: #{e.message}", :unprocessable_entity)
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

    private

    def find_temp_attachment
      # Sécurité: on ne peut supprimer que les fichiers de sa propre session ou utilisateur
      scope = TemporaryAttachment.where(session_id: current_session_id)
      scope = scope.or(TemporaryAttachment.where(user_id: current_user&.id)) if current_user

      @temp_attachment = scope.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_error("Fichier non trouvé ou accès refusé", :not_found)
    end

    def render_temp_file_list(attribute_name)
      files = TemporaryAttachment.for_session(current_session_id)
                                  .for_attribute(attribute_name)

      if turbo_stream_request?
        render_turbo_stream_replace(
          "udnd_files_list_#{attribute_name}",
          partial: "upload_d_n_d/shared/temp_files_list",
          locals: { files: files, attribute_name: attribute_name }
        )
      else
        respond_to do |format|
          format.json { render json: { status: 'ok', message: 'Fichier temporaire créé' }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: 'Fichier ajouté' }
          format.any { render json: { status: 'ok', message: 'Fichier temporaire créé' }, status: :ok }
        end
      end
    end

    def log_deletion
      Rails.logger.info "UploadDND: Temporary file deleted - #{@temp_attachment.attribute_name} by #{current_user&.id || 'anonymous'}"
    end

    # === Autorisation ===

    def authorize_upload!
      return unless pundit_enabled?

      authorize :upload_d_n_d_temporary_attachment, :create?
    rescue Pundit::NotAuthorizedError
      render_error("Vous n'êtes pas autorisé à uploader des fichiers", :forbidden)
    end

    def authorize_delete!
      return unless pundit_enabled?

      authorize :upload_d_n_d_temporary_attachment, :destroy?
    rescue Pundit::NotAuthorizedError
      render_error("Vous n'êtes pas autorisé à supprimer ce fichier", :forbidden)
    end
  end
end
