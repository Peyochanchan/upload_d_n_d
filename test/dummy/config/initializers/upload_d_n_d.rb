# Démonstration dans un navigateur (bin/rails server) : pas d'authentification,
# autorisation désactivée, et limites globales volontairement plus étroites que
# celles de DemoProject. Les specs gardent la configuration par défaut.
if Rails.env.development?
  UploadDND.configure do |config|
    config.require_authentication = false
    config.authorization_adapter = :none
    config.max_size = 2.megabytes
    config.accepted_types = ".pdf"
  end
end
