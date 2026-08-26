# frozen_string_literal: true

module UploadDND
  module UploadAuthorization
    extend ActiveSupport::Concern

    included do
      before_action :authorize_upload!, only: [ :create ]
      before_action :authorize_destroy!, only: [ :destroy ]
    end

    private

    # Vérifie si l'utilisateur peut uploader sur cet attribut
    # Peut être surchargée dans votre controller
    def authorize_upload!
      # Si vous utilisez Pundit
      if defined?(Pundit)
        authorize_with_pundit
      # Si vous utilisez CanCanCan
      elsif defined?(CanCan)
        authorize_with_cancan
      else
        # Autorisation par défaut : l'utilisateur doit être connecté
        authorize_basic_upload!
      end
    end

    # Vérifie si l'utilisateur peut supprimer ce fichier
    def authorize_destroy!
      if defined?(Pundit)
        authorize @temp_attachment || @attachment
      elsif defined?(CanCan)
        authorize! :destroy, @temp_attachment || @attachment
      else
        authorize_basic_destroy!
      end
    end

    # Autorisation basique : utilisateur connecté
    def authorize_basic_upload!
      return if current_user.present?

      render json: { error: "Vous devez être connecté pour uploader des fichiers" },
             status: :unauthorized
    end

    def authorize_basic_destroy!
      # Vérifie que le fichier appartient à la session ou à l'utilisateur
      return if owner_matches_current_user?

      render json: { error: "Vous ne pouvez pas supprimer ce fichier" },
             status: :forbidden
    end

    def authorize_with_pundit
      record = find_or_build_record
      authorize record, :update?
    end

    def authorize_with_cancan
      record = find_or_build_record
      authorize! :update, record
    end

    def owner_matches_current_user?
      if @temp_attachment
        @temp_attachment.session_id == UploadDND::SessionId.for(session) ||
          @temp_attachment.user_id == current_user&.id
      elsif @attachment
        @attachment.record.user_id == current_user&.id if @attachment.record.respond_to?(:user_id)
      end
    end

    def find_or_build_record
      if params[:record_gid].present?
        GlobalID::Locator.locate(params[:record_gid])
      else
        # Pour les uploads temporaires, on ne peut pas vraiment autoriser
        # car le record n'existe pas encore
        nil
      end
    end

    def current_user
      # À adapter selon votre système d'authentification
      # Par défaut, on suppose que vous utilisez Devise ou similaire
      respond_to?(:current_user, true) ? super : nil
    end
  end
end
