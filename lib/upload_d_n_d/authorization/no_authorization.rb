# frozen_string_literal: true

module UploadDND
  module Authorization
    # authorization_adapter = :none — opt-out explicite : seule
    # l'authentification est vérifiée. Signalé au démarrage.
    module NoAuthorization
      module_function

      def authorize!(_controller, _subject, _action, namespace: nil); end
    end
  end
end
