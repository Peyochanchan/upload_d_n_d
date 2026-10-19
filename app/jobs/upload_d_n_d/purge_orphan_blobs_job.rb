# frozen_string_literal: true

module UploadDND
  # Nettoie les blobs orphelins listés par UploadDND::OrphanBlobs. Opt-in : la
  # gem fournit le job, l'app hôte le planifie (voir README, "Nettoyage
  # automatique"). apply: false (défaut) journalise un rapport sans supprimer ;
  # l'app passe apply: true en connaissance de cause.
  class PurgeOrphanBlobsJob < ApplicationJob
    queue_as :default

    def perform(apply: false)
      results = UploadDND::OrphanBlobs.call
      purgeable = results.select(&:purgeable?)

      purgeable.each { |result| result.blob.purge } if apply

      size = ActiveSupport::NumberHelper.number_to_human_size(purgeable.sum { |result| result.blob.byte_size })
      Rails.logger.info(
        "UploadDND::PurgeOrphanBlobsJob: #{purgeable.size} blob(s) orphelin(s) " \
        "#{apply ? "purgé(s)" : "à purger (simulation)"} (#{size}), " \
        "#{results.size - purgeable.size} cité(s) dans un texte et conservé(s)."
      )
    end
  end
end
