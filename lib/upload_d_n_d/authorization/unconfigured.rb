# frozen_string_literal: true

module UploadDND
  module Authorization
    # Aucun adaptateur utilisable (nil, valeur inconnue) : tout est refusé.
    module Unconfigured
      module_function

      def authorize!(_controller, subject, action, namespace: nil) # rubocop:disable Lint/UnusedMethodArgument
        Rails.logger.warn "UploadDND: #{action} on #{subject.class} refused - no authorization adapter configured"
        raise Denied
      end
    end
  end
end
