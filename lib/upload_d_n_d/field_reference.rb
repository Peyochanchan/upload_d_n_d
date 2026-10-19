# frozen_string_literal: true

module UploadDND
  # Référence signée d'un champ (modèle + attribut), émise par le composant et
  # renvoyée au dépôt : le serveur retrouve les limites du champ sans faire
  # confiance au client. Elle ne porte pas les limites elles-mêmes : le modèle
  # reste la seule autorité.
  module FieldReference
    PURPOSE = :upload_d_n_d_field

    class Invalid < UploadDND::Error; end

    class << self
      def generate(model_class, attribute_name)
        verifier.generate([ model_class.name, attribute_name.to_s ], purpose: PURPOSE)
      end

      # @raise [Invalid] signature fausse, autre attribut, modèle ou attachment inconnu
      # @return [UploadDND::FieldConstraints]
      def constraints(token, attribute_name)
        model_name, attribute = verified(token)
        raise Invalid unless attribute.present? && attribute == attribute_name.to_s

        model_class = model_name.to_s.safe_constantize
        raise Invalid unless model_class.respond_to?(:reflect_on_attachment) && model_class.reflect_on_attachment(attribute)

        FieldConstraints.for(model_class, attribute)
      end

      private

      def verified(token)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        payload.is_a?(Array) && payload.size == 2 ? payload : raise(Invalid)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
        raise Invalid
      end

      def verifier
        Rails.application.message_verifier("upload_d_n_d/field_reference")
      end
    end
  end
end
