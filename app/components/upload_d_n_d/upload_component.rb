module UploadDND
  class UploadComponent < ViewComponent::Base
    attr_reader :record, :attribute_name, :multiple, :accepted_types, :max_size, :user, :namespace

    def initialize(
      attribute_name:,
      record: nil,
      user: nil,
      multiple: nil,
      accepted_types: nil,
      max_size: nil,
      namespace: nil
    )
      @record = record
      @user = user
      @attribute_name = attribute_name
      @namespace = namespace

      # Récupère la config depuis le modèle si disponible, sinon utilise les params ou la config globale
      model_config = get_uploadable_config

      # Détection automatique de multiple basée sur has_one vs has_many
      # Peut être surchargé explicitement via le paramètre ou la config du modèle
      @multiple = if multiple.nil?
        model_config[:multiple].nil? ? detect_multiple_from_attachment : model_config[:multiple]
      else
        multiple
      end

      @accepted_types = accepted_types || model_config[:accepted_types] || UploadDND.configuration.accepted_types
      @max_size = max_size || model_config[:max_size] || UploadDND.configuration.max_size
    end

    def model_name
      return attribute_name.to_s.singularize unless record

      # Convertit "Admin::Article" en "admin_article" (pour les IDs DOM)
      record.class.name.underscore.tr("/", "_")
    end

    # Génère le GlobalID pour le record (fonctionne avec tous les namespaces)
    def record_gid
      # Un record non persisté n'a pas d'ID => GlobalID impossible (MissingModelIdError).
      return nil unless record&.persisted?

      record.to_global_id.to_s
    end

    # Détermine l'URL d'attachement : soit vers le moteur de la gem, soit vers une route spécifique
    def attach_path
      action_path = record&.persisted? ? :attachments_path : :temporary_attachments_path

      # Si pas de namespace, on utilise les routes internes de l'engine (plus robuste)
      return UploadDND::Engine.routes.url_helpers.send(action_path) if namespace.blank?

      # Avec namespace, on utilise polymorphic_path pour supporter les routes de l'app hôte
      begin
        action = record&.persisted? ? :attachments : :temporary_attachments
        helpers.polymorphic_path([ namespace, :upload_d_n_d, action ])
      rescue NoMethodError, ArgumentError, ViewComponent::HelpersCalledBeforeRenderError
        # En cas d'erreur (ex: helpers non dispos avant render), fallback sur l'engine
        UploadDND::Engine.routes.url_helpers.send(action_path)
      end
    end

    def files
      if record&.persisted?
        get_attachments
      else
        # Logique de récupération temporaire via la table dédiée de la gem
        UploadDND::TemporaryAttachment.where(
          session_id: helpers.session.id.to_s,
          attribute_name: attribute_name
        )
      end
    end

    # --- Thème / Couleurs ---
    # Exposé pour permettre au composant d'injecter des variables CSS cohérentes
    def main_color
      UploadDND.configuration.main_color.presence || "#E97451"
    end

    # Renvoie "r g b" (ex: "233 116 81") pour usage avec `rgb(var(--udnd-accent-rgb) / 0.2)`
    def main_color_rgb
      hex = main_color.to_s.delete_prefix("#")
      hex = hex.chars.map { |c| "#{c}#{c}" }.join if hex.length == 3

      return "233 116 81" unless hex.match?(/\A[0-9a-fA-F]{6}\z/)

      r = hex[0..1].to_i(16)
      g = hex[2..3].to_i(16)
      b = hex[4..5].to_i(16)
      "#{r} #{g} #{b}"
    end

    private

    def get_uploadable_config
      return {} unless record

      # Récupère la classe du modèle (gère les namespaces)
      model_class = record.class

      # Vérifie si le modèle a la méthode uploadable_attributes
      return {} unless model_class.respond_to?(:uploadable_attributes)

      # Récupère la config pour cet attribut spécifique
      config = model_class.uploadable_attributes[attribute_name.to_sym]
      return {} unless config

      # Convertit les MIME types en extensions pour l'affichage
      accepted_types_string = if config[:content_type]
        mime_types_to_extensions(config[:content_type])
      else
        nil
      end

      {
        accepted_types: accepted_types_string,
        max_size: config[:max_size],
        multiple: config[:multiple]
      }
    end

    # Détecte automatiquement si l'attachment est has_one ou has_many
    def detect_multiple_from_attachment
      return false unless record&.respond_to?(attribute_name)

      attachment = record.send(attribute_name)

      # has_many_attached retourne une collection qui respond_to :attach
      # has_one_attached retourne un objet qui ne respond_to pas :each
      attachment.is_a?(ActiveStorage::Attached::Many)
    end

    def mime_types_to_extensions(mime_types)
      # Mapping MIME types vers extensions
      mime_to_ext = {
        "image/jpeg" => ".jpg",
        "image/png" => ".png",
        "image/gif" => ".gif",
        "image/webp" => ".webp",
        "image/svg+xml" => ".svg",
        "application/pdf" => ".pdf",
        "application/msword" => ".doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
        "application/vnd.ms-excel" => ".xls",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
        "application/vnd.ms-powerpoint" => ".ppt",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation" => ".pptx",
        "application/vnd.oasis.opendocument.text" => ".odt",
        "text/plain" => ".txt",
        "text/csv" => ".csv",
        "application/zip" => ".zip"
      }

      mime_types.map { |mime| mime_to_ext[mime] || mime }.join(",")
    end

    def get_attachments
      return [] unless record&.respond_to?(attribute_name)

      attachment = record.public_send(attribute_name)
      case attachment
      when ActiveStorage::Attached::Many
        attachment.blobs
      when ActiveStorage::Attached::One
        attachment.attached? ? [attachment.blob] : []
      else
        []
      end
    end
  end
end
