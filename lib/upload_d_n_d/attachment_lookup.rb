# frozen_string_literal: true

module UploadDND
  # Résout un attachment ActiveStorage à partir d'un nom d'attribut venu du
  # client (paramètre de requête, ou attribute_name stocké dans un
  # TemporaryAttachment).
  #
  # SÉCURITÉ : seule la réflexion du modèle fait foi. Un nom qui ne désigne pas
  # un attachment déclaré (has_one_attached / has_many_attached) n'est jamais
  # appelé sur le record — `respond_to?` + `send` laisserait passer `destroy`,
  # `delete`, `touch`...
  module AttachmentLookup
    # @return [ActiveStorage::Attached::One, ActiveStorage::Attached::Many, nil]
    def self.find(record, attribute_name)
      return if record.nil? || attribute_name.blank?
      return unless record.class.respond_to?(:reflect_on_attachment)

      name = attribute_name.to_s
      return unless record.class.reflect_on_attachment(name)

      record.public_send(name)
    end
  end
end
