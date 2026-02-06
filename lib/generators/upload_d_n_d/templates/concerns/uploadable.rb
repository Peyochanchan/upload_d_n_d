# frozen_string_literal: true

module UploadDND
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
      # @option options [Array<Symbol>] :accept extensions acceptées (ex: [:jpg, :png, :pdf])
      # @option options [Array<String>] :content_type types MIME autorisés (alternative à :accept)
      # @option options [Integer] :max_size la taille max en bytes
      # @option options [Integer] :max_files le nombre max de fichiers (pour has_many)
      # @option options [Boolean] :multiple autoriser plusieurs fichiers (déclare has_many_attached)
      # @option options [String] :message message d'erreur personnalisé
      # @option options [Boolean] :strict_mime_check active la détection MIME côté serveur (anti-spoofing)
      # @option options [String] :spoofing_message message d'erreur personnalisé pour les erreurs de spoofing
      #
      # @example Image unique (has_one_attached déclaré automatiquement)
      #   class User < ApplicationRecord
      #     include UploadDND::Uploadable
      #
      #     uploadable :avatar,
      #                accept: [:jpg, :png],
      #                max_size: 5.megabytes,
      #                strict_mime_check: true
      #   end
      #
      # @example Documents multiples (has_many_attached déclaré automatiquement)
      #   class Project < ApplicationRecord
      #     include UploadDND::Uploadable
      #
      #     uploadable :documents,
      #                accept: [:pdf, :doc, :docx],
      #                max_size: 10.megabytes,
      #                multiple: true,
      #                max_files: 5,
      #                strict_mime_check: true
      #   end
      def uploadable(attribute_name, **options)
        validates attribute_name,
                  file: options.slice(:content_type, :max_size, :max_files, :message, :strict_mime_check, :spoofing_message)

        # Stocke les options pour usage ultérieur
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
        next unless respond_to?(attribute_name)

        # SÉCURITÉ : Détection serveur du type d'attachment (has_one vs has_many)
        attachment = send(attribute_name)

        if attachment.is_a?(ActiveStorage::Attached::Many)
          # has_many_attached: ajouter à la collection
          attachment.attach(temp_attachment.blob.blob)
        elsif attachment.is_a?(ActiveStorage::Attached::One)
          # has_one_attached: utiliser = (remplace automatiquement)
          # Ne transférer que le PREMIER fichier temporaire si plusieurs existent
          unless attachment.attached?
            send("#{attribute_name}=", temp_attachment.blob.blob)
          end
        end

        temp_attachment.destroy
      end

      # Nettoie le session_id après utilisation
      @_temp_upload_session_id = nil
    end
  end
end
