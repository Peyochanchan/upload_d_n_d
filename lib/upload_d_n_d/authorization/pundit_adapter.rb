# frozen_string_literal: true

module UploadDND
  module Authorization
    # Adaptateur Pundit : `authorize sujet, :action?` sur le contrôleur, qui
    # doit inclure Pundit::Authorization (verify_authorized reste satisfait).
    module PunditAdapter
      module_function

      def authorize!(controller, subject, action, namespace: nil)
        unless defined?(::Pundit) && controller.respond_to?(:authorize, true)
          raise ConfigurationError,
                "authorization_adapter is :pundit but #{controller.class} cannot call authorize " \
                "(Pundit missing or Pundit::Authorization not included)"
        end

        call(controller, subject, :"#{action}?", namespace)
      end

      # Avec un namespace, la policy namespacée (authorize [:admin, record] ->
      # Admin::RecordPolicy) est essayée d'abord, puis la policy top-level : un
      # namespace de contrôleur (module: dans les routes) ne reflète pas
      # forcément celui des policies.
      def call(controller, subject, query, namespace)
        if namespace.present?
          begin
            return controller.send(:authorize, [ *namespace, subject ], query)
          rescue ::Pundit::NotDefinedError
            nil # repli sur la policy top-level
          end
        end

        controller.send(:authorize, subject, query)
      rescue ::Pundit::NotAuthorizedError
        raise Denied
      rescue ::Pundit::NotDefinedError
        raise RuleMissing
      end
    end
  end
end
