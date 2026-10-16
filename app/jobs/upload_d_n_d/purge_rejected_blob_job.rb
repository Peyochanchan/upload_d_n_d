# frozen_string_literal: true

module UploadDND
  # Purge un blob refusé (cf. UploadDND::RejectedBlob).
  #
  # Contrairement à ActiveStorage::PurgeJob, revérifie au moment de
  # l'exécution que le blob n'a toujours aucun attachment : il a pu être
  # rattaché entre le refus et l'exécution du job (nouvel essai réussi avec le
  # même signed_id). L'âge n'est pas revérifié : il a été contrôlé au refus, et
  # le délai de la file ne doit pas empêcher la purge.
  class PurgeRejectedBlobJob < ApplicationJob
    queue_as { ActiveStorage.queues[:purge] }

    retry_on ActiveRecord::Deadlocked, attempts: 10, wait: :polynomially_longer

    def perform(blob_id)
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return unless blob
      return unless UploadDND::RejectedBlob.unattached?(blob)

      blob.purge
    end
  end
end
