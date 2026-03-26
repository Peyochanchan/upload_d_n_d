# frozen_string_literal: true

# Configuration de UploadDND
UploadDND.configure do |config|
  # Taille maximale par défaut des fichiers (en bytes)
  # Peut être surchargé au niveau du composant
  config.max_size = 10.megabytes

  # Types de fichiers acceptés par défaut
  # Peut être surchargé au niveau du composant
  config.accepted_types = ".pdf,.doc,.docx,.jpg,.jpeg,.png,.gif"

  # Vérification stricte du type MIME (anti-spoofing)
  # Analyse le contenu réel du fichier via Marcel (plus coûteux)
  # config.strict_mime_check = false

  # Couleur principale du thème (utilisée pour les boutons, progress bar, etc.)
  config.main_color = "#E97451"

  # Autoriser les uploads sans authentification (déconseillé en production)
  # config.allow_anonymous_uploads = false

  # Durée de conservation des fichiers temporaires (en jours)
  # Les fichiers temporaires non attachés seront supprimés après ce délai
  # config.temporary_files_retention = 7

  # Classe utilisée pour l'autorisation (Pundit, CanCanCan, ou nil)
  # Détection automatique par défaut
  # config.authorization_adapter = :pundit # ou :cancancan, ou nil

  # Validateur personnalisé
  # Par défaut, utilise FileValidator si disponible
  # config.validator_class = 'FileValidator'

  # Configuration du stockage ActiveStorage (optionnel)
  # Exemple: forcer l'utilisation d'un service spécifique
  # config.active_storage_service = :amazon

  # Callbacks personnalisés
  # config.on_upload_success = ->(blob, user) {
  #   # Logger ou notifier
  #   Rails.logger.info "File uploaded: #{blob.filename} by #{user&.email}"
  # }
  #
  # config.on_upload_error = ->(error, user) {
  #   # Logger ou notifier
  #   Rails.logger.error "Upload failed: #{error.message} for #{user&.email}"
  # }

  # Rate limiting (nécessite rack-attack ou similaire)
  # config.rate_limit_enabled = true
  # config.rate_limit_max_requests = 10
  # config.rate_limit_period = 1.minute
end
