# frozen_string_literal: true

module UploadDND
  module Authorization
    # Adaptateur CanCanCan : `authorize! :action, sujet` sur le contrôleur.
    # Les sujets génériques sont des symboles, à autoriser dans l'Ability :
    #   can :create, :upload_d_n_d_attachment
    # Sans règle, CanCanCan refuse : il n'y a pas de RuleMissing.
    module CanCanCanAdapter
      module_function

      def authorize!(controller, subject, action, namespace: nil) # rubocop:disable Lint/UnusedMethodArgument
        unless defined?(::CanCan::AccessDenied) && controller.respond_to?(:authorize!, true)
          raise ConfigurationError,
                "authorization_adapter is :cancancan but #{controller.class} cannot call authorize! " \
                "(CanCanCan missing)"
        end

        call(controller, subject, action)
      end

      def call(controller, subject, action)
        controller.send(:authorize!, action, subject)
      rescue ::CanCan::AccessDenied
        raise Denied
      end
    end
  end
end
