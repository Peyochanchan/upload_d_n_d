# frozen_string_literal: true

module UploadDND
  module ApplicationHelper
    # URL de suppression d'un fichier attaché.
    #
    # Mode :engine (défaut) : route DELETE du moteur de la gem, identifiée
    # par record_gid — aucune route requise côté app, quel que soit le
    # routing du record (imbriqué, singulier, namespacé).
    #
    # Mode :host (legacy, config.delete_route = :host) : route membre
    # remove_file du record côté app (convention : resources + member
    # remove_file). Nécessite une route polymorphique — voir README,
    # section "Records imbriqués". Point d'extension : redéfinissez cette
    # méthode dans le ApplicationHelper de votre app.
    def udnd_remove_file_url(record, attachment, attribute_name, namespace: nil)
      if UploadDND.configuration.delete_route == :host
        query = { file_id: attachment.id, attribute_name: attribute_name }.to_query
        "#{udnd_record_path(record)}/remove_file?#{query}"
      else
        # Jeton régénéré côté serveur : il survit aux re-rendus Turbo Stream du
        # partial (les boutons de suppression portent toujours une cible valide).
        token = UploadDND::SignedTarget.generate(
          record.class, attribute_name, record_id: record.id, namespace: namespace
        )
        UploadDND::Engine.routes.url_helpers.attachment_path(attachment.id, target: token)
      end
    end

    def udnd_record_path(record)
      main_app.polymorphic_path(record)
    rescue NoMethodError, ActionController::UrlGenerationError
      raise UploadDND::UnroutableRecordError, <<~MSG
        #{record.class.name} n'a pas de route polymorphique : impossible de
        construire l'URL de suppression de fichier.

        Deux remèdes :

        1. Déclarer la résolution polymorphique dans config/routes.rb (recommandé).
           Exemple pour une resource singulière imbriquée
           (resource :convention sous resources :projects) :

             resolve("Convention") { |convention, options| route_for(:project_convention, convention.project, options) }

        2. Ou surcharger udnd_remove_file_url(record, attachment, attribute_name)
           dans le ApplicationHelper de votre app.

        Voir la section "Records imbriqués" du README de upload_d_n_d.
      MSG
    end
  end
end
