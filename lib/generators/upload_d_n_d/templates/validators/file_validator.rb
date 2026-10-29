# frozen_string_literal: true

# Validateur de fichiers pour ActiveStorage
# Utilise Marcel pour la détection MIME et vérifie le contenu réel des fichiers
#
# @example Utilisation avec has_one_attached
#   class User < ApplicationRecord
#     has_one_attached :avatar
#
#     validates :avatar, file: {
#       content_type: ['image/png', 'image/jpeg'],
#       max_size: 5.megabytes
#     }
#   end
#
# @example Utilisation avec has_many_attached
#   class Project < ApplicationRecord
#     has_many_attached :documents
#
#     validates :documents, file: {
#       content_type: ['application/pdf', 'application/msword'],
#       max_size: 10.megabytes,
#       max_files: 5
#     }
#   end
#
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

  # Valide le content_type déclaré
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

  # Valide la taille du fichier
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

  # Valide le nombre de fichiers (pour has_many_attached)
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

  # Détecte le vrai type MIME en analysant le contenu du fichier
  # Protège contre le spoofing de fichiers (ex: .exe renommé en .jpg)
  def validate_mime_type(record, attribute, file)
    return unless options[:content_type].present?

    begin
      # Marcel analyse le contenu réel du fichier pour détecter son type
      detected_content_type = detect_content_type(record, attribute, file)

      declared_content_type = file.content_type

      # Vérifie que le type détecté est dans la liste des types autorisés
      unless detected_content_type.in?(Array(options[:content_type]))
        record.errors.add(
          attribute,
          :spoofed_content_type,
          message: options[:spoofing_message] ||
                  "Le type de fichier détecté (#{detected_content_type}) ne correspond pas aux types autorisés"
        )
      end

      # Vérifie que le type détecté correspond au type déclaré
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
      record.errors.add(
        attribute,
        :mime_type_detection_failed,
        message: "Impossible de vérifier le type de fichier : #{e.message}"
      )
    end
  end

  # Marcel a besoin des octets du fichier. Avec un champ fichier classique, le
  # fichier part avec le formulaire et n'est envoyé au stockage qu'après le
  # `save` : à la validation, `file.download` lèverait
  # `ActiveStorage::FileNotFoundError`. On lit alors la source encore en attente
  # (`attachment_changes`) sans la consommer pour l'envoi au stockage. Avec un
  # blob déjà stocké (zone de dépôt), on retombe sur `file.download`.
  def detect_content_type(record, attribute, file)
    io = pending_upload_io(record, attribute, file)
    return Marcel::MimeType.for(file.download, name: file.filename.to_s) unless io

    io.rewind if io.respond_to?(:rewind)
    Marcel::MimeType.for(io, name: file.filename.to_s)
  ensure
    io.rewind if io.respond_to?(:rewind)
  end

  def pending_upload_io(record, attribute, file)
    return unless record.respond_to?(:attachment_changes)

    change = record.attachment_changes[attribute.to_s]
    return unless change

    blob = file.respond_to?(:blob) ? file.blob : file
    attachable = pending_attachables_by_key(change)[blob&.key]
    attachable && readable_io(attachable)
  end

  # { blob.key => attachable } des sources non encore stockées. has_one :
  # CreateOne (blob + attachable). has_many : CreateMany (blobs + attachables,
  # même ordre). La `key` est fiable avant le save (l'id du blob est encore nil).
  def pending_attachables_by_key(change)
    if change.respond_to?(:blobs) && change.respond_to?(:attachables)
      change.blobs.map(&:key).zip(change.attachables).to_h
    elsif change.respond_to?(:blob) && change.respond_to?(:attachable)
      { change.blob&.key => change.attachable }
    else
      {}
    end
  end

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
