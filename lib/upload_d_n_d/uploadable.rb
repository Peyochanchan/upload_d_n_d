# frozen_string_literal: true

module UploadDND
  # Concern modèle pour déclarer des attachments "uploadables" et transférer
  # automatiquement les fichiers temporaires lors de la création d'un record.
  #
  # Remarque: ce module existait historiquement comme template de générateur.
  # Il est maintenant livré par la gem pour éviter un prérequis implicite
  # (et coller au README).
  module Uploadable
    extend ActiveSupport::Concern

    included do
      # Callbacks pour attacher les fichiers temporaires après création
      after_create :attach_temporary_uploads
    end

    # Stocke temporairement le session_id pour l'upload
    # Utilise une variable d'instance privée plutôt qu'attr_accessor
    def temp_upload_session_id=(value)
      @_temp_upload_session_id = value
    end

    def temp_upload_session_id
      @_temp_upload_session_id
    end

    class_methods do
      # Déclare un champ uploadable avec validation
      #
      # @param attribute_name [Symbol] le nom de l'attribut (ex: :avatar, :documents)
      # @param options [Hash] les options de validation
      # @option options [Array<String>] :content_type les types MIME autorisés
      # @option options [Integer] :max_size la taille max en bytes
      # @option options [Integer] :max_files le nombre max de fichiers (pour has_many)
      # @option options [Boolean] :multiple autoriser plusieurs fichiers (auto-détecté depuis has_one/has_many par défaut)
      # @option options [String] :message message d'erreur personnalisé
      # @option options [Boolean] :strict_mime_check active la détection MIME côté serveur (anti-spoofing, plus coûteux)
      # @option options [String] :spoofing_message message d'erreur personnalisé pour les erreurs de spoofing
      def uploadable(attribute_name, **options)
        # Résoudre accept: en content_type: (symboles → MIME strings)
        if options[:accept]
          options[:content_type] = UploadDND::MimeTypes.resolve(options.delete(:accept))
        end

        # Auto-déclarer has_one_attached / has_many_attached si pas déjà fait
        unless reflect_on_attachment(attribute_name)
          if options[:multiple]
            has_many_attached attribute_name
          else
            has_one_attached attribute_name
          end
        end

        validates attribute_name,
                  file: options.slice(:content_type, :max_size, :max_files, :message, :strict_mime_check, :spoofing_message)

        # Stocke les options pour usage ultérieur (ViewComponent, helpers, etc.)
        (@uploadable_attributes ||= {})[attribute_name] = options
      end

      def uploadable_attributes
        @uploadable_attributes || {}
      end
    end

    private

    def attach_temporary_uploads
      return unless temp_upload_session_id.present?
      return unless UploadDND::TemporaryAttachment.exists?(session_id: temp_upload_session_id)

      UploadDND::TemporaryAttachment.where(session_id: temp_upload_session_id).find_each do |temp_attachment|
        attribute_name = temp_attachment.attribute_name

        # SÉCURITÉ : attribute_name vient du client — seul un attachment déclaré
        # sur le modèle est résolu. Détection serveur du type (has_one vs has_many).
        attachment = UploadDND::AttachmentLookup.find(self, attribute_name)
        unless attachment
          # Si l'attribut n'est pas un attachment du record, on nettoie quand même
          # pour éviter de laisser des fichiers orphelins en base.
          temp_attachment.destroy
          next
        end

        blob_attachment = temp_attachment.blob_attachment
        if blob_attachment.nil? || temp_attachment.violates_constraints_of?(self, attribute_name)
          temp_attachment.destroy
          next
        end

        if attachment.is_a?(ActiveStorage::Attached::Many)
          # has_many_attached: on "déplace" l'attachment (pas de purge du blob)
          blob_attachment.update!(record: self, name: attribute_name)
        elsif attachment.is_a?(ActiveStorage::Attached::One)
          # has_one_attached: utiliser = (remplace automatiquement)
          # Ne transférer que le PREMIER fichier temporaire si plusieurs existent
          if attachment.attached?
            # Le record a déjà un fichier: on purgera le temporaire.
            temp_attachment.destroy
            next
          end

          blob_attachment.update!(record: self, name: attribute_name)
        end

        # Après déplacement, temp_attachment n'a plus d'attachment ActiveStorage.
        # On reload pour éviter les caches d'association avant destroy.
        temp_attachment.reload
        temp_attachment.destroy
      end

      # Nettoie le session_id après utilisation
      @_temp_upload_session_id = nil
    end
  end
end
