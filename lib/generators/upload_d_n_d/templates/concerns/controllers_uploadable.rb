# frozen_string_literal: true

module UploadDND
  module Controllers
    module Uploadable
      extend ActiveSupport::Concern

      # Action pour attacher un fichier à un record existant
      # POST /:resource/:id/attach_file
      def attach_file
        record = instance_variable_get("@#{controller_name.singularize}")
        attribute_name = params[:attribute_name]
        blob_id = params[:blob_id]

        unless record
          render json: { error: "Enregistrement non trouvé" }, status: :not_found
          return
        end

        unless attribute_name.present? && blob_id.present?
          render json: { error: "Paramètres manquants" }, status: :bad_request
          return
        end

        # Récupère le blob ActiveStorage
        begin
          blob = ActiveStorage::Blob.find(blob_id)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Fichier non trouvé" }, status: :not_found
          return
        end

        # Attache le blob au record
        attachment = record.send(attribute_name)
        if attachment.respond_to?(:attach)
          attachment.attach(blob)
        else
          record.send("#{attribute_name}=", blob)
        end

        if record.save
          render_file_list(record, attribute_name)
        else
          render json: { error: record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # Action pour supprimer un fichier d'un record
      # DELETE /:resource/:id/remove_file
      def remove_file
        record = instance_variable_get("@#{controller_name.singularize}")
        attribute_name = params[:attribute_name]
        file_id = params[:file_id]

        unless record
          render json: { error: "Enregistrement non trouvé" }, status: :not_found
          return
        end

        unless attribute_name.present? && file_id.present?
          render json: { error: "Paramètres manquants" }, status: :bad_request
          return
        end

        # Sécurité : vérifie que l'attribut existe et est un attachement
        unless record.respond_to?(attribute_name)
          render json: { error: "Attribut inexistant" }, status: :unprocessable_entity
          return
        end

        # Trouve et supprime l'attachment
        begin
          attachment = ActiveStorage::Attachment.find(file_id)

          # Sécurité : vérifie que l'attachment appartient bien à ce record
          unless attachment.record_id == record.id && attachment.name == attribute_name
            render json: { error: "Accès refusé" }, status: :forbidden
            return
          end

          attachment.purge
          render_file_list(record, attribute_name)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Fichier non trouvé" }, status: :not_found
        end
      end

      # Lie les uploads temporaires (session) au record avant save
      # Utiliser dans l'action create :
      #   wire_temporary_uploads(@record)
      def wire_temporary_uploads(record)
        sid = params[:temp_upload_session_id]
        if sid.present? && sid == session.id.to_s
          record.temp_upload_session_id = sid
        end
      end

      private

      def render_file_list(record, attribute_name)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "udnd_files_list_#{attribute_name}",
              partial: "upload_d_n_d/shared/files_list",
              locals: { record: record, attribute_name: attribute_name }
            )
          end
          format.json { render json: { status: 'ok' }, status: :ok }
          format.html { redirect_back fallback_location: root_path, notice: 'Fichier mis à jour' }
        end
      end
    end
  end
end
