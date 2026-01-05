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
  end
end
