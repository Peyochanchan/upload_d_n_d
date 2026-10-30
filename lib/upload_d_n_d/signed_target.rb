# frozen_string_literal: true

module UploadDND
  # Cible d'upload signée : modèle + attribut + (record) + namespace de policy,
  # émise par UploadComponent et vérifiée par les contrôleurs du moteur. Elle
  # remplace les paramètres bruts `record_gid` / `attribute_name` / `namespace`
  # du client : le serveur ne fait plus confiance au client pour désigner la
  # cible ni le namespace d'autorisation.
  #
  # - Permanent (record persisté) : record_id présent → le record est résolu
  #   par `model_class.find(record_id)` (sûr, puisque le couple est signé).
  # - Temporaire (record non persisté) : record_id nil.
  #
  # Garde-fou : l'attribut doit être déclaré via `uploadable` sur le modèle
  # (pas seulement un `has_one_attached`/`has_many_attached` quelconque).
  module SignedTarget
    PURPOSE = :upload_d_n_d_target

    class Invalid < UploadDND::Error; end

    Target = Data.define(:model_class, :attribute, :record_id, :namespace) do
      # Résout le record signé. Lève ActiveRecord::RecordNotFound s'il a disparu
      # (traduit en 404 par le contrôleur). nil pour une cible temporaire.
      def record
        return nil if record_id.nil?

        model_class.find(record_id)
      end

      def constraints
        UploadDND::FieldConstraints.for(model_class, attribute)
      end
    end

    class << self
      # @param record_id [Object, nil] id du record (nil pour une cible temporaire)
      # @param namespace [Array<Symbol>, nil] namespace de policy
      def generate(model_class, attribute, record_id: nil, namespace: nil)
        payload = [ model_class.name, attribute.to_s, record_id, Array(namespace).map(&:to_s).presence ]
        verifier.generate(payload, purpose: PURPOSE)
      end

      # @raise [Invalid] signature fausse, charge malformée, modèle inconnu, ou
      #   attribut non déclaré `uploadable`
      # @return [Target]
      def verify(token)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        raise Invalid unless payload.is_a?(Array) && payload.size == 4

        model_name, attribute, record_id, namespace = payload
        model_class = model_name.to_s.safe_constantize
        raise Invalid unless model_class && uploadable?(model_class, attribute)

        Target.new(
          model_class: model_class,
          attribute: attribute.to_s,
          record_id: record_id,
          namespace: namespace&.map(&:to_sym)
        )
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
        raise Invalid
      end

      def uploadable?(model_class, attribute)
        model_class.respond_to?(:uploadable_attributes) &&
          model_class.uploadable_attributes.key?(attribute.to_sym)
      end

      private

      def verifier
        Rails.application.message_verifier("upload_d_n_d/signed_target")
      end
    end
  end
end
