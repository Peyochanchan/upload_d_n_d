# frozen_string_literal: true

module UploadDND
  # Port d'autorisation : la question que la gem pose — « l'utilisateur
  # courant peut-il faire <action> sur <sujet> ? » — indépendamment de la
  # librairie qui y répond. Chaque librairie est un adaptateur, choisi par
  # config.authorization_adapter.
  #
  # Fail-closed : un adaptateur absent (nil) ou inconnu refuse tout.
  # L'absence d'autorisation ne s'obtient qu'explicitement, avec :none.
  module Authorization
    # Refus. `cause` porte l'exception native de la librairie, s'il y en a une.
    class Denied < UploadDND::Error; end

    # Aucune règle pour ce sujet (Pundit : policy absente). L'appelant décide
    # du repli ; à défaut, l'erreur remonte (500).
    class RuleMissing < UploadDND::Error; end

    # Adaptateur déclaré mais inutilisable (librairie absente, contrôleur sans
    # la méthode d'autorisation).
    class ConfigurationError < UploadDND::Error; end

    class << self
      # @param controller [ActionController::Base] contrôleur de la requête
      # @param subject [Object, Symbol] record, ou symbole d'une policy générique
      # @param action [Symbol] :create, :update, :destroy...
      # @param namespace [Array<Symbol>, nil] namespace de policy à essayer d'abord
      # @raise [Denied, RuleMissing, ConfigurationError]
      def authorize!(controller, subject, action, namespace: nil)
        adapter.authorize!(controller, subject, action, namespace: namespace)
      end

      def adapter(name = UploadDND.configuration.authorization_adapter)
        key = name.respond_to?(:to_sym) ? name.to_sym : name
        adapters.fetch(key, Unconfigured)
      end

      # Avertit au démarrage quand les uploads ne sont pas protégés par une
      # librairie d'autorisation.
      def report(logger = Rails.logger)
        configured = UploadDND.configuration.authorization_adapter
        current = adapter(configured)

        if current == NoAuthorization
          logger.warn "UploadDND: authorization disabled (authorization_adapter = :none) - " \
                      "uploads and deletions are only checked for authentication"
        elsif current == Unconfigured
          logger.warn "UploadDND: no usable authorization adapter (authorization_adapter = #{configured.inspect}) - " \
                      "all uploads and deletions are refused. Set config.authorization_adapter " \
                      "to :pundit, :cancancan or :none."
        end
      end

      private

      def adapters
        { pundit: PunditAdapter, cancancan: CanCanCanAdapter, none: NoAuthorization }
      end
    end
  end
end

require "upload_d_n_d/authorization/pundit_adapter"
require "upload_d_n_d/authorization/can_can_can_adapter"
require "upload_d_n_d/authorization/no_authorization"
require "upload_d_n_d/authorization/unconfigured"
