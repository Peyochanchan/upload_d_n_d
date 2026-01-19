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

    # Cette ligne permet d'ajouter les assets de la gem au pipeline de l'app hôte
    initializer "upload_d_n_d.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
      # Si l'app utilise Importmap, on "pin" le contrôleur
      if app.config.respond_to?(:importmap)
        app.config.importmap.draw(root.join("config/importmap.rb"))
      end
    end

    # Vérifie les mises à jour disponibles au démarrage de Rails
    initializer "upload_d_n_d.check_updates", after: :load_config_initializers do
      config.after_initialize do
        # Ne s'exécute qu'en développement pour ne pas polluer les logs en production
        next unless Rails.env.development?

        # Charge le VersionTracker
        require_relative "version_tracker"

        # Affiche la notification si une mise à jour est disponible
        if UploadDND::VersionTracker.update_available?
          notice = UploadDND::VersionTracker.update_notice
          Rails.logger.info(notice) if notice
          # Affiche aussi dans la console pour plus de visibilité
          puts notice if notice && defined?(Rails::Console)
        end
      end
    end
  end
end
