module UploadDND
  class Engine < ::Rails::Engine
    isolate_namespace UploadDND

    # Configuration des acronymes pour que Rails reconnaisse DND
    initializer "upload_d_n_d.inflections" do
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym "DND"
      end

      ActiveSupport::Inflector.inflections(:fr) do |inflect|
        inflect.acronym "DND"
      end
    end

    # Helpers de la gem disponibles dans les vues de l'app hôte
    # (les partials de la gem sont rendus depuis les controllers de l'app,
    # qui n'incluent pas les helpers d'un engine isolé par défaut)
    initializer "upload_d_n_d.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper UploadDND::Engine.helpers
      end
    end

    # Uploads non protégés par une librairie d'autorisation : signalé au
    # démarrage, une fois les initializers de l'app passés.
    config.after_initialize do
      UploadDND::Authorization.report
    end

    # Assets : JS (importmap) + CSS (asset pipeline)
    initializer "upload_d_n_d.assets" do |app|
      # JS : rend les fichiers disponibles pour importmap
      app.config.assets.paths << root.join("app/javascript")

      # CSS : rend upload_d_n_d/application.css disponible via stylesheet_link_tag
      app.config.assets.paths << root.join("app/assets/stylesheets")

      # Importmap : pin automatique des controllers Stimulus
      if app.config.respond_to?(:importmap)
        app.config.importmap.draw(root.join("config/importmap.rb"))
      end
    end
  end
end
