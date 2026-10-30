# frozen_string_literal: true

# Génère des cibles signées (UploadDND::SignedTarget) pour les specs, comme le
# ferait UploadComponent côté vue.
module SignedTargetHelper
  # Cible pour un record (persisté → record_id présent ; sinon temporaire).
  def signed_target_for(record, attribute, namespace: nil)
    UploadDND::SignedTarget.generate(
      record.class, attribute,
      record_id: (record.id if record.persisted?),
      namespace: namespace
    )
  end

  # Cible temporaire (modèle seul, pas de record).
  def temp_target_for(model_class, attribute, namespace: nil)
    UploadDND::SignedTarget.generate(model_class, attribute, record_id: nil, namespace: namespace)
  end
end

RSpec.configure do |config|
  config.include SignedTargetHelper
end
