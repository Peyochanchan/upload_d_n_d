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
      # Transfère les fichiers temporaires d'une session vers un record.
      #
      # @param attribute_map [Hash, nil] mapping source => cible. nil (callback
      #   after_create) = identité sur les attributs `uploadable` du modèle.
      #
      # SÉCURITÉ (F3) : on ne traite que les attributs explicitement demandés
      # (clés de `attribute_map`, ou les `uploadable_attributes` du modèle), et
      # seulement s'ils sont déclarés `uploadable` — un attribute_name forgé vers
      # un autre champ (ex. "signed_contract") n'est jamais transféré.
      # SÉCURITÉ (F4) : `max_files` et les contraintes du champ sont vérifiés au
      # transfert (le déplacement par `update!` ne relance pas la validation).
      def attach_to_record(session_id, record, attribute_map = nil)
        uploadable = record.class.respond_to?(:uploadable_attributes) ? record.class.uploadable_attributes : {}
        counts = Hash.new { |hash, attr| hash[attr] = current_attachment_count(record, attr) }

        for_session(session_id).find_each do |temp_attachment|
          target_attr = resolve_target(temp_attachment.attribute_name, attribute_map)
          next if target_attr.nil? # non demandé explicitement : on laisse (nettoyage orphelins)

          unless uploadable.key?(target_attr.to_sym)
            temp_attachment.destroy # champ non uploadable : fichier non légitime
            next
          end

          attachment = UploadDND::AttachmentLookup.find(record, target_attr)
          blob_attachment = temp_attachment.blob_attachment
          if attachment.nil? || blob_attachment.nil? || temp_attachment.violates_constraints_of?(record, target_attr)
            temp_attachment.destroy
            next
          end

          if attachment.is_a?(ActiveStorage::Attached::Many)
            max = uploadable[target_attr.to_sym][:max_files]
            if max && counts[target_attr] >= max
              Rails.logger.warn "UploadDND: #{record.class}##{target_attr} max_files (#{max}) atteint au transfert - fichier refusé"
              temp_attachment.destroy
              next
            end
            blob_attachment.update!(record: record, name: target_attr)
            counts[target_attr] += 1
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

      private

      # Cible pour un attribut source. Avec une map : uniquement ses clés (nil
      # sinon). Sans map (after_create) : identité (filtré ensuite sur uploadable).
      def resolve_target(source_attr, attribute_map)
        return source_attr if attribute_map.nil?

        attribute_map[source_attr]&.to_s
      end

      def current_attachment_count(record, attribute)
        attachment = UploadDND::AttachmentLookup.find(record, attribute)
        case attachment
        when ActiveStorage::Attached::Many then attachment.count
        when ActiveStorage::Attached::One then attachment.attached? ? 1 : 0
        else 0
        end
      end
    end

    # Méthodes d'instance

    # Le transfert vers le record ne passe pas par la validation du modèle :
    # les limites du champ cible sont vérifiées ici. Couvre aussi un dépôt
    # fait sans référence de champ (limites globales seulement).
    def violates_constraints_of?(record, attribute_name)
      violation = UploadDND::FieldConstraints.for(record.class, attribute_name).violation(blob.blob)
      return false unless violation

      Rails.logger.warn "UploadDND: temporary file #{id} refused on transfer to " \
                        "#{record.class}##{attribute_name} - #{violation}"
      true
    end
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
      # polymorphic_url respecte config.active_storage.resolve_model_to_route
      # de l'app hôte (:rails_storage_redirect par défaut, :rails_storage_proxy
      # pour servir les blobs en same-origin — CSP stricte, bucket externe).
      # only_path: true explicite : la forme _path ne le propage pas aux
      # routes `resolve` d'ActiveStorage hors contexte de requête.
      Rails.application.routes.url_helpers.polymorphic_url(blob.blob, only_path: true) if blob.attached?
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
