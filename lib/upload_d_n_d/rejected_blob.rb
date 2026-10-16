# frozen_string_literal: true

module UploadDND
  # Blob envoyé par DirectUpload puis refusé par le serveur (contraintes,
  # validation du modèle, erreur à l'enregistrement).
  #
  # Avec l'envoi direct, le fichier est déjà dans le bucket quand le serveur
  # le contrôle : sans purge, chaque refus (et chaque nouvel essai) laisse un
  # blob orphelin.
  #
  # Règle : on ne supprime jamais un fichier qui appartient à quelqu'un. Le
  # signed_id vient du navigateur, il peut désigner un blob existant :
  # - un blob qui a un attachment (record, ou TemporaryAttachment) est intact ;
  # - un blob ancien est intact, même sans attachment : il peut être cité dans
  #   un HTML stocké (sgid, URL) — seul un envoi récent est purgé.
  module RejectedBlob
    # Programme la purge du blob s'il est purgeable. La purge effective
    # revérifie l'absence d'attachment (cf. PurgeRejectedBlobJob).
    def self.discard(blob)
      return unless discardable?(blob)

      Rails.logger.info "UploadDND: rejected blob #{blob.id} scheduled for purge"
      UploadDND::PurgeRejectedBlobJob.perform_later(blob.id)
    end

    def self.discardable?(blob)
      blob.is_a?(ActiveStorage::Blob) &&
        blob.persisted? &&
        recent?(blob) &&
        unattached?(blob)
    end

    def self.unattached?(blob)
      !blob.attachments.exists?
    end

    def self.recent?(blob)
      window = UploadDND.configuration.rejected_blob_purge_window
      window.present? && blob.created_at >= window.ago
    end
  end
end
