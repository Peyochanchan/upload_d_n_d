# frozen_string_literal: true

module UploadDND
  module ApplicationHelper
    # URL de suppression d'un fichier attaché, construite sur la route membre
    # remove_file du record (convention : resources :xxx + member remove_file).
    #
    # Point d'extension officiel : redéfinissez cette méthode dans le
    # ApplicationHelper de votre app pour un routing exotique. Pour les
    # resources imbriquées ou singulières, préférez déclarer un resolve()
    # dans config/routes.rb — voir README, section "Records imbriqués".
    def udnd_remove_file_url(record, attachment, attribute_name)
      query = { file_id: attachment.id, attribute_name: attribute_name }.to_query
      "#{udnd_record_path(record)}/remove_file?#{query}"
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
