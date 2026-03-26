# frozen_string_literal: true

module UploadDND
  module UploadHelper
    # Rendu du composant d'upload
    #
    # @param attribute_name [Symbol] le nom de l'attribut (ex: :avatar, :documents)
    # @param record [ApplicationRecord, nil] le record à attacher (nil pour upload temporaire)
    # @param options [Hash] options supplémentaires
    # @option options [Boolean] :multiple (false) autoriser plusieurs fichiers
    # @option options [String] :accepted_types types de fichiers acceptés (ex: '.jpg,.png')
    # @option options [Integer] :max_size taille max en bytes
    # @option options [String] :label label personnalisé
    # @option options [Hash] :validation_options options passées au FileValidator
    #
    # @example Upload simple
    #   <%= upload_field :avatar, record: @user %>
    #
    # @example Upload multiple avec validation
    #   <%= upload_field :documents,
    #                    record: @project,
    #                    multiple: true,
    #                    accepted_types: '.pdf,.docx',
    #                    max_size: 10.megabytes %>
    #
    # @example Upload temporaire (record pas encore créé)
    #   <%= upload_field :logo, accepted_types: '.png,.jpg' %>
    #
    def upload_field(attribute_name, record: nil, **options)
      render UploadDND::UploadComponent.new(
        attribute_name: attribute_name,
        record: record,
        user: current_user_for_upload,
        **options
      )
    end

    # Génère un champ caché avec le session_id pour les uploads temporaires.
    # À placer dans les formulaires qui créent un nouveau record avec upload.
    def upload_session_field
      tag.input(type: "hidden", name: "temp_upload_session_id", value: session.id.to_s)
    end

    # Affiche la liste des fichiers uploadés
    #
    # @param attribute_name [Symbol] le nom de l'attribut
    # @param record [ApplicationRecord] le record
    #
    def uploaded_files_list(attribute_name, record:)
      return unless record&.respond_to?(attribute_name)

      attachments = record.send(attribute_name)
      return unless attachments.attached?

      files = attachments.respond_to?(:each) ? attachments : [ attachments ]

      render partial: "upload_d_n_d/shared/files_list",
             locals: { files: files, attribute_name: attribute_name }
    end

    # Récupère l'utilisateur courant pour l'upload
    # Peut être surchargé dans votre application
    def current_user_for_upload
      respond_to?(:current_user, true) ? current_user : nil
    end

    # Icône selon le type de fichier
    def file_icon_class(filename)
      extension = File.extname(filename).downcase

      case extension
      when ".pdf"
        "fa-file-pdf"
      when ".doc", ".docx"
        "fa-file-word"
      when ".xls", ".xlsx"
        "fa-file-excel"
      when ".jpg", ".jpeg", ".png", ".gif", ".svg"
        "fa-file-image"
      when ".zip", ".rar", ".7z"
        "fa-file-archive"
      when ".mp4", ".avi", ".mov"
        "fa-file-video"
      else
        "fa-file"
      end
    end

    # Badge de couleur selon le type
    def file_type_badge_class(content_type)
      case content_type
      when /^image\//
        "badge-success"
      when /^application\/pdf/
        "badge-danger"
      when /^application\/.*word/
        "badge-primary"
      when /^application\/.*excel/, /^application\/.*spreadsheet/
        "badge-success"
      else
        "badge-secondary"
      end
    end
  end
end
