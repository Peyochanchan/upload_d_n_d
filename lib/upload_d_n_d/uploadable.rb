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

        # On référence UploadDND::FileValidator explicitement (plutôt que la clé
        # `file:`, qui résout un `::FileValidator` global et masquerait le
        # validateur de l'app hôte).
        validates_with UploadDND::FileValidator,
                       attributes: [ attribute_name ],
                       **options.slice(:content_type, :max_size, :max_files, :message, :strict_mime_check, :spoofing_message)

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

      # Délègue au transfert durci (restreint aux champs `uploadable`, applique
      # max_files et les contraintes du champ au transfert — cf. F3/F4).
      UploadDND::TemporaryAttachment.attach_to_record(temp_upload_session_id, self)

      # Nettoie le session_id après utilisation
      @_temp_upload_session_id = nil
    end
  end
end
