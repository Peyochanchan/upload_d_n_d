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

  # Un fichier refusé par le serveur (taille, type, validation...) est purgé
  # s'il a été envoyé dans cette fenêtre et n'est rattaché à rien.
  # nil désactive la purge des fichiers refusés.
  # config.rejected_blob_purge_window = 1.hour

  # Nettoyage des blobs orphelins (opt-in : UploadDND::PurgeOrphanBlobsJob ou
  # la tâche rake upload_d_n_d:purge_orphans). PostgreSQL requis.
  # config.orphan_blob_min_age = 2.days
  # Limite le scan des citations aux colonnes de texte riche (borne la mémoire).
  # Sans liste, toutes les colonnes texte/JSON sont scannées.
  # config.orphan_scan_columns = ["projects.description", "pages.body_translations"]
  # Motifs d'adresse supplémentaires (hôte/bucket du service de stockage).
  # config.orphan_scan_patterns = ["%votre-bucket.example.com%"]
  # config.orphan_scan_excluded_tables = []

  # Autorisation : :pundit ou :cancancan (détection automatique), ou :none
  # pour s'en passer. Sans adaptateur utilisable, tout est refusé (403).
  # config.authorization_adapter = :pundit # ou :cancancan, ou :none

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

  # Rate limiting (compteur basé sur Rails.cache ; aucune gem requise)
  # config.rate_limit_enabled = true
  # config.rate_limit_max_requests = 10
  # config.rate_limit_period = 1.minute
end
