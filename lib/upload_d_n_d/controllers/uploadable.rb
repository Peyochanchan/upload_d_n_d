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
            flash[:alert] = "Le fichier semble corrompu ou modifié"
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: "Le fichier semble corrompu" }, status: :unprocessable_entity }
        end
      end

      rescue_from ActiveStorage::UnrepresentableError do |_e|
        respond_to do |format|
          format.turbo_stream do
            flash[:alert] = "Le fichier n'est pas traitable"
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: "Le fichier n'est pas traitable" }, status: :unprocessable_entity }
        end
      end
    end

    # Attache un fichier à un record existant
    # Utilise les fichiers temporaires uploadés via UploadDND
    #
    # @param record [ApplicationRecord] le record sur lequel attacher
    # @param attribute_name [String, Symbol] le nom de l'attribut (ex: :avatar, :documents)
    def attach_upload_d_n_d_files(record, attribute_name)
      # Récupère les fichiers temporaires de la session pour cet attribut
      temp_attachments = UploadDND::TemporaryAttachment.for_session(session.id.to_s)
                                                        .for_attribute(attribute_name.to_s)

      temp_attachments.each do |temp|
        # Attache le blob au record
        record.send(attribute_name).attach(temp.blob.blob)

        # Nettoie le fichier temporaire
        temp.destroy
      end
    end

    # Autorise un record pour update (compatible avec Pundit namespaces)
    #
    # @param record [ApplicationRecord] le record à autoriser
    def authorize_record_for_update(record)
      return unless defined?(Pundit)

      if controller_namespace
        # Avec namespace : authorize [:namespace, record], :update?
        namespace_symbol = controller_namespace.underscore.to_sym
        authorize [namespace_symbol, record], :update?
      else
        # Sans namespace : authorize record, :update?
        authorize record, :update?
      end
    end

    # Action pour attacher un fichier à un record existant (appelée via route de l'app)
    # Route attendue : POST /:model_name/:id/attach_file
    def attach_file
      # Utilise l'instance variable définie par before_action (ex: @project)
      record = instance_variable_get("@#{controller_name.singularize}")

      # Si pas d'instance variable, cherche le record
      unless record
        model_name = params[:model_name] || controller_name.singularize
        record = find_record_for_upload(model_name, params[:id])
      end

      authorize_record_for_update(record)

      blob = ActiveStorage::Blob.find_signed(params[:signed_blob_id])
      attribute_name = params[:attribute_name]

      record.send(attribute_name).attach(blob)

      if record.save
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = "Fichier ajouté avec succès"
            render turbo_stream: [
              turbo_stream.replace(
                "udnd_files_list_#{attribute_name}",
                partial: "upload_d_n_d/shared/files_list",
                locals: { record: record.reload, attribute_name: attribute_name }
              ),
              turbo_stream.replace("flash_messages", partial: "shared/flashes")
            ]
          end
          format.json { render json: { status: 'ok' }, status: :ok }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = record.errors.full_messages.join(", ")
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: record.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    # Action pour supprimer un fichier d'un record existant (appelée via route de l'app)
    # Route attendue : DELETE /:model_name/:id/remove_file
    def remove_file
      # Utilise l'instance variable définie par before_action (ex: @project)
      record = instance_variable_get("@#{controller_name.singularize}")

      # Si pas d'instance variable, cherche le record
      unless record
        model_name = params[:model_name] || controller_name.singularize
        record = find_record_for_upload(model_name, params[:id])
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
            flash.now[:notice] = "Fichier supprimé avec succès"
            render turbo_stream: [
              turbo_stream.replace(
                "udnd_files_list_#{attribute_name}",
                partial: "upload_d_n_d/shared/files_list",
                locals: { record: record, attribute_name: attribute_name }
              ),
              turbo_stream.replace("flash_messages", partial: "shared/flashes")
            ]
          end
          format.json { render json: { status: 'ok' }, status: :ok }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = "Fichier non trouvé ou accès refusé"
            render turbo_stream: turbo_stream.replace("flash_messages", partial: "shared/flashes")
          end
          format.json { render json: { error: "Fichier non trouvé" }, status: :not_found }
        end
      end
    end

    private

    # Retourne le namespace du controller si présent
    # Ex: Admin::ProjectsController => "Admin"
    def controller_namespace
      controller_class = self.class.name.to_s
      namespace_parts = controller_class.split("::")
      namespace_parts.length > 1 ? namespace_parts.first : nil
    end

    # Trouve le record pour l'upload
    def find_record_for_upload(model_name, record_id)
      model_class = model_name.classify.constantize
      model_class.find(record_id)
    end
    end
  end
end
