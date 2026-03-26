# frozen_string_literal: true

module UploadDND
  class TemporaryAttachment < ApplicationRecord
    self.table_name = "upload_d_n_d_temporary_attachments"

    # Association avec ActiveStorage
    has_one_attached :blob

    # Validations
    validates :session_id, presence: true
    validates :attribute_name, presence: true

    # Scopes
    scope :for_session, ->(session_id) { where(session_id: session_id) }
    scope :for_attribute, ->(attribute_name) { where(attribute_name: attribute_name) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :expired, -> {
      retention_days = UploadDND.configuration.temporary_files_retention || 7
      where("created_at < ?", retention_days.days.ago)
    }
    # Eager load blob attachments to prevent N+1 queries
    scope :with_blobs, -> { includes(blob_attachment: :blob) }

    # Callbacks
    before_destroy :purge_blob

    # Méthodes de classe
    class << self
      # Nettoie les fichiers temporaires expirés
      # À appeler via un job cron ou Sidekiq
      def cleanup_expired!
        expired.find_each do |attachment|
          attachment.destroy
        end
      end

      # Attache tous les fichiers temporaires d'une session à un record
      #
      # @param session_id [String] l'ID de session
      # @param record [ApplicationRecord] le record cible
      # @param attribute_map [Hash] mapping des attributs (optionnel)
      #
      # @example
      #   TemporaryAttachment.attach_to_record(
      #     session.id.to_s,
      #     @user,
      #     { 'avatar' => :avatar, 'documents' => :documents }
      #   )
      def attach_to_record(session_id, record, attribute_map = {})
        for_session(session_id).find_each do |temp_attachment|
          source_attr = temp_attachment.attribute_name
          target_attr = attribute_map[source_attr]&.to_s || source_attr

          unless record.respond_to?(target_attr)
            temp_attachment.destroy
            next
          end

          attachment = record.send(target_attr)
          blob_attachment = temp_attachment.blob_attachment
          unless blob_attachment
            temp_attachment.destroy
            next
          end

          if attachment.is_a?(ActiveStorage::Attached::Many)
            blob_attachment.update!(record: record, name: target_attr)
          elsif attachment.is_a?(ActiveStorage::Attached::One)
            if attachment.attached?
              temp_attachment.destroy
              next
            end
            blob_attachment.update!(record: record, name: target_attr)
          end

          temp_attachment.reload
          temp_attachment.destroy
        end
      end
    end

    # Méthodes d'instance
    def filename
      blob.blob.filename.to_s if blob.attached?
    end

    def content_type
      blob.blob.content_type if blob.attached?
    end

    def byte_size
      blob.blob.byte_size if blob.attached?
    end

    def url
      Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true) if blob.attached?
    end

    private

    def purge_blob
      # Si l'attachment ActiveStorage a été "déplacé" vers un autre record,
      # `blob_attachment` sera nil (après reload) -> on ne purge rien.
      return unless blob_attachment

      blob.purge if blob.attached?
    end
  end
end
