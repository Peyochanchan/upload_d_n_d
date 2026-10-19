# frozen_string_literal: true

module UploadDND
  # Limites d'un champ d'upload : taille maximale, types MIME acceptés,
  # contrôle MIME strict. Source unique pour le composant, les contrôleurs et
  # le transfert des fichiers temporaires.
  #
  # Value object (Data) : immuable, deux instances aux mêmes valeurs sont
  # égales. Construit depuis `uploadable` du modèle ; chaque limite que le
  # modèle ne déclare pas retombe sur la configuration globale.
  FieldConstraints = Data.define(:max_size, :content_types, :strict_mime_check) do
    class << self
      def for(model_class, attribute_name)
        options = uploadable_options(model_class, attribute_name)
        return global unless options

        config = UploadDND.configuration
        new(
          max_size: options[:max_size] || config.max_size,
          content_types: options[:content_type] || MimeTypes.from_accepted_types(config.accepted_types),
          strict_mime_check: options.key?(:strict_mime_check) ? options[:strict_mime_check] : config.strict_mime_check
        )
      end

      def global
        config = UploadDND.configuration
        new(
          max_size: config.max_size,
          content_types: MimeTypes.from_accepted_types(config.accepted_types),
          strict_mime_check: config.strict_mime_check
        )
      end

      private

      def uploadable_options(model_class, attribute_name)
        return unless model_class.respond_to?(:uploadable_attributes)

        model_class.uploadable_attributes[attribute_name.to_sym]
      end
    end

    def initialize(max_size:, content_types:, strict_mime_check:)
      super(
        max_size: max_size,
        content_types: Array(content_types).map(&:to_s).uniq.freeze,
        strict_mime_check: strict_mime_check == true
      )
    end

    # Extensions pour l'attribut `accept` et les messages : ".jpg,.jpeg,.png"
    def accepted_extensions
      MimeTypes.to_extensions(content_types)
    end

    # @return [Symbol, nil] :too_large, :invalid_type, :suspicious_type ou
    #   :mime_detection_failed ; nil si le blob respecte les limites
    def violation(blob)
      return :too_large if max_size.present? && blob.byte_size > max_size
      return if content_types.empty?
      return :invalid_type unless content_types.include?(blob.content_type)

      detected_type_violation(blob) if strict_mime_check
    end

    def error_message(violation)
      case violation
      when :too_large
        I18n.t("upload_d_n_d.errors.too_large", max_size: ActiveSupport::NumberHelper.number_to_human_size(max_size))
      when :invalid_type
        I18n.t("upload_d_n_d.errors.invalid_type", types: accepted_extensions)
      else
        I18n.t("upload_d_n_d.errors.#{violation}")
      end
    end

    private

    # Anti-spoofing : type réel lu dans le contenu. Le détail d'un échec reste
    # dans les logs, jamais dans la réponse.
    def detected_type_violation(blob)
      detected = Marcel::MimeType.for(blob.download, name: blob.filename.to_s)
      return if detected.blank?
      return :invalid_type unless content_types.include?(detected)

      :suspicious_type unless detected == blob.content_type
    rescue StandardError => e
      Rails.logger.warn "UploadDND: MIME detection failed - #{e.class}: #{e.message}"
      :mime_detection_failed
    end
  end
end
