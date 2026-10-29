# frozen_string_literal: true

# Validateur de fichiers pour ActiveStorage.
#
# Rails associe `validates :avatar, file: {...}` à une constante `FileValidator`.
# Pour garder l'API ergonomique, on expose `UploadDND::FileValidator` ET on
# fournit un alias top-level `::FileValidator` si absent.
module UploadDND
  class FileValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return unless value.attached?

      Array(value).each do |file|
        validate_content_type(record, attribute, file)
        validate_size(record, attribute, file)
        validate_mime_type(record, attribute, file) if options[:strict_mime_check]
      end

      validate_file_count(record, attribute, value) if value.respond_to?(:count)
    end

    private

    def validate_content_type(record, attribute, file)
      return unless options[:content_type].present?

      unless file.content_type.in?(Array(options[:content_type]))
        record.errors.add(
          attribute,
          :content_type,
          message: options[:message] || "n'est pas un type de fichier valide"
        )
      end
    end

    def validate_size(record, attribute, file)
      return unless options[:max_size].present?

      if file.byte_size > options[:max_size]
        max_size_in_mb = options[:max_size] / 1.megabyte
        record.errors.add(
          attribute,
          :max_size,
          message: options[:message] || "doit être inférieur à #{max_size_in_mb}MB"
        )
      end
    end

    def validate_file_count(record, attribute, value)
      return unless options[:max_files].present?

      if value.count > options[:max_files]
        record.errors.add(
          attribute,
          :max_files,
          message: options[:message] || "ne peut pas avoir plus de #{options[:max_files]} fichiers"
        )
      end
    end

    # Détecte le vrai type MIME en analysant le contenu du fichier (anti-spoofing).
    def validate_mime_type(record, attribute, file)
      return unless options[:content_type].present?

      detected_content_type = detect_content_type(record, attribute, file)
      declared_content_type = file.content_type

      unless detected_content_type.in?(Array(options[:content_type]))
        record.errors.add(
          attribute,
          :spoofed_content_type,
          message: options[:spoofing_message] ||
                  "Le type de fichier détecté (#{detected_content_type}) ne correspond pas aux types autorisés"
        )
      end

      if detected_content_type != declared_content_type
        record.errors.add(
          attribute,
          :mime_type_mismatch,
          message: options[:spoofing_message] ||
                  "Le type de fichier détecté (#{detected_content_type}) " \
                  "ne correspond pas au type déclaré (#{declared_content_type})"
        )
      end
    rescue StandardError => e
      # Le détail reste dans les logs : le message d'erreur est affiché.
      Rails.logger.warn "UploadDND: MIME detection failed - #{e.class}: #{e.message}"
      record.errors.add(
        attribute,
        :mime_type_detection_failed,
        message: I18n.t("upload_d_n_d.errors.mime_detection_failed")
      )
    end

    # Marcel a besoin des octets du fichier. Avec la zone de dépôt, le blob est
    # déjà sur le stockage et `file.download` suffit. Avec un champ fichier
    # classique, le fichier part avec le formulaire et n'est envoyé au stockage
    # qu'après le `save` : à la validation, `file.download` lèverait
    # `ActiveStorage::FileNotFoundError`. On lit alors la source encore en
    # attente (`attachment_changes`), sans la consommer pour l'envoi au stockage.
    def detect_content_type(record, attribute, file)
      io = pending_upload_io(record, attribute, file)
      return Marcel::MimeType.for(file.download, name: file.filename.to_s) unless io

      io.rewind if io.respond_to?(:rewind)
      Marcel::MimeType.for(io, name: file.filename.to_s)
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    # IO de la source non encore stockée pour ce fichier, ou nil si le blob est
    # déjà sur le stockage (zone de dépôt, signed_id, blob existant).
    def pending_upload_io(record, attribute, file)
      return unless record.respond_to?(:attachment_changes)

      change = record.attachment_changes[attribute.to_s]
      return unless change

      blob = file.respond_to?(:blob) ? file.blob : file
      attachable = pending_attachables_by_key(change)[blob&.key]
      attachable && readable_io(attachable)
    end

    # { blob.key => attachable } des sources non encore stockées. La `key` est
    # fiable même avant le save (l'id du blob est encore nil, donc pas de
    # comparaison par id). has_one : CreateOne (blob + attachable). has_many :
    # CreateMany (blobs + attachables, même ordre). Une suppression ne crée rien.
    def pending_attachables_by_key(change)
      if change.respond_to?(:blobs) && change.respond_to?(:attachables)
        change.blobs.map(&:key).zip(change.attachables).to_h
      elsif change.respond_to?(:blob) && change.respond_to?(:attachable)
        { change.blob&.key => change.attachable }
      else
        {}
      end
    end

    # Extrait un IO des sources d'upload gérées. Les autres (signed_id, blob
    # déjà stocké) renvoient nil pour retomber sur `file.download`. Duck typing
    # volontaire : `Rack::Test::UploadedFile` n'est pas chargé en production, on
    # ne référence donc pas la constante.
    def readable_io(attachable)
      if attachable.respond_to?(:tempfile) # UploadedFile (ActionDispatch / Rack::Test)
        attachable.tempfile
      elsif attachable.is_a?(Hash)
        attachable[:io]
      elsif attachable.respond_to?(:read) # IO, File, StringIO...
        attachable
      end
    end
  end
end

# Alias top-level pour l'API `validates ..., file: ...`
::FileValidator = UploadDND::FileValidator unless defined?(::FileValidator)
