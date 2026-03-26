# frozen_string_literal: true

# Acronymes de l'app
# Permet notamment de constantiser correctement `upload_dnd/*` en `UploadDND::*`
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "DND"
end

ActiveSupport::Inflector.inflections(:fr) do |inflect|
  inflect.acronym "DND"
end
