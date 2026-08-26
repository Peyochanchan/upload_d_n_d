# frozen_string_literal: true

module UploadDND
  # Purge les fichiers temporaires expirés (au-delà de
  # temporary_files_retention jours, 7 par défaut).
  #
  # La gem fournit le job mais ne le planifie pas : brancher la récurrence
  # côté app hôte (solid_queue recurring, sidekiq-cron, whenever...).
  # Voir la section "Nettoyage automatique" du README.
  class CleanupTemporaryAttachmentsJob < ApplicationJob
    queue_as :default

    def perform
      TemporaryAttachment.cleanup_expired!
    end
  end
end
