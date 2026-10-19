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

      # Limites du champ, identiques à celles appliquées par le serveur.
      # accepted_types: et max_size: ne changent que l'affichage : le serveur
      # applique toujours les limites du modèle.
      @constraints = field_constraints
      @accepted_types = accepted_types || @constraints.accepted_extensions
      @max_size = max_size || @constraints.max_size
    end

    # Types MIME acceptés, pour le contrôle du navigateur
    def accepted_mime_types
      return @constraints.content_types.join(",") if @accepted_types == @constraints.accepted_extensions

      UploadDND::MimeTypes.from_accepted_types(@accepted_types).join(",")
    end

    # Référence signée du champ, renvoyée au dépôt : le serveur en déduit les
    # limites du modèle. nil sans record (limites globales).
    def field_ref
      return unless record && record.class.respond_to?(:reflect_on_attachment)
      return unless record.class.reflect_on_attachment(attribute_name)

      UploadDND::FieldReference.generate(record.class, attribute_name)
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
        # Fichiers temporaires de la session courante (formulaire sans record persisté)
        UploadDND::TemporaryAttachment
          .for_session(UploadDND::SessionId.for(helpers.session))
          .for_attribute(attribute_name)
          .with_blobs
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

    def field_constraints
      return UploadDND::FieldConstraints.global unless record

      UploadDND::FieldConstraints.for(record.class, attribute_name)
    end

    def get_uploadable_config
      return {} unless record&.class.respond_to?(:uploadable_attributes)

      record.class.uploadable_attributes[attribute_name.to_sym] || {}
    end

    # Détecte automatiquement si l'attachment est has_one ou has_many
    def detect_multiple_from_attachment
      return false unless record&.respond_to?(attribute_name)

      attachment = record.send(attribute_name)

      # has_many_attached retourne une collection qui respond_to :attach
      # has_one_attached retourne un objet qui ne respond_to pas :each
      attachment.is_a?(ActiveStorage::Attached::Many)
    end

    def get_attachments
      return [] unless record&.respond_to?(attribute_name)

      attachment = record.public_send(attribute_name)
      case attachment
      when ActiveStorage::Attached::Many
        attachment.blobs
      when ActiveStorage::Attached::One
        attachment.attached? ? [ attachment.blob ] : []
      else
        []
      end
    end

    # Retourne les messages i18n pour JavaScript
    def i18n_messages
      {
        alerts: {
          singleFileOnly: {
            title: I18n.t("upload_d_n_d.javascript.alerts.single_file_only.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.single_file_only.text")
          },
          uploadError: {
            title: I18n.t("upload_d_n_d.javascript.alerts.upload_error.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.upload_error.text")
          },
          fileTooLarge: {
            title: I18n.t("upload_d_n_d.javascript.alerts.file_too_large.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.file_too_large.text")
          },
          emptyFile: {
            title: I18n.t("upload_d_n_d.javascript.alerts.empty_file.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.empty_file.text")
          },
          invalidFormat: {
            title: I18n.t("upload_d_n_d.javascript.alerts.invalid_format.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.invalid_format.text")
          },
          suspiciousType: {
            title: I18n.t("upload_d_n_d.javascript.alerts.suspicious_type.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.suspicious_type.text")
          },
          attachError: {
            title: I18n.t("upload_d_n_d.javascript.alerts.attach_error.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.attach_error.text")
          },
          deleteError: {
            title: I18n.t("upload_d_n_d.javascript.alerts.delete_error.title"),
            text: I18n.t("upload_d_n_d.javascript.alerts.delete_error.text")
          }
        },
        confirms: {
          deleteFile: {
            title: I18n.t("upload_d_n_d.javascript.confirms.delete_file.title"),
            text: I18n.t("upload_d_n_d.javascript.confirms.delete_file.text"),
            confirmButton: I18n.t("upload_d_n_d.javascript.confirms.delete_file.confirm_button"),
            cancelButton: I18n.t("upload_d_n_d.javascript.confirms.delete_file.cancel_button")
          }
        }
      }
    end
  end
end
