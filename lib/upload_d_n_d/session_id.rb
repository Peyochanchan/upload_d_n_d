# frozen_string_literal: true

module UploadDND
  # Identifiant de session utilisé pour scoper les fichiers temporaires.
  #
  # Sur une session vierge (aucun cookie), `session.id` est nil tant que rien
  # n'a été écrit en session : le premier upload échouerait (session_id vide)
  # et l'id lu au rendu du formulaire ne correspondrait pas à celui des uploads.
  #
  # `SessionId.for` amorce la session en y écrivant une clé neutre, ce qui force
  # l'émission d'un id et du cookie dès la réponse courante, quel que soit le store.
  # L'id est ainsi stable entre le rendu du composant et les requêtes suivantes.
  module SessionId
    KEY = "upload_d_n_d.session"

    def self.for(session)
      return "" if session.nil?

      session[KEY] ||= true if session.respond_to?(:[]=)

      sid = session.respond_to?(:id) ? session.id : (session[:id] || session["id"])
      sid.to_s
    end
  end
end
