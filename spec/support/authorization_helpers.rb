# frozen_string_literal: true

# Pundit n'est pas dans le bundle de test : on simule ses constantes et on
# sélectionne l'adaptateur :pundit.
module AuthorizationHelpers
  def stub_pundit!
    stub_const('Pundit', Module.new)
    stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
    stub_const('Pundit::NotDefinedError', Class.new(StandardError))
    UploadDND.configuration.authorization_adapter = :pundit
  end
end

RSpec.configure do |config|
  config.include AuthorizationHelpers
end
