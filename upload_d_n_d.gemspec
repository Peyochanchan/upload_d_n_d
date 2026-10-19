require_relative "lib/upload_d_n_d/version"

Gem::Specification.new do |spec|
  spec.name        = "upload_d_n_d"
  spec.version     = UploadDND::VERSION
  spec.authors     = [ "Pierre Cherbero" ]
  spec.email       = [ "cameleon24@outlook.fr" ]
  spec.summary     = "Système de drag & drop sécurisé pour Rails avec ActiveStorage"
  spec.description = "UploadDND fournit une interface drag & drop élégante et sécurisée pour vos uploads de fichiers dans Rails. Basé sur ActiveStorage, Stimulus et ViewComponent, il offre une validation serveur robuste, un support d'upload temporaire, et une intégration facile avec Pundit/CanCanCan."
  spec.license     = "MIT"

  # Dépôt privé : pas d'URL publique tant que la publication n'est pas tranchée.

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "docs/CHANGELOG.md"]
  end

  # Testé sur Rails 8.1. La borne haute < 8.2 doit être relâchée (et une version
  # publiée) avant qu'une app hôte monte en Rails 8.2.
  spec.add_dependency "rails", ">= 7.2.3", "< 8.2"
  spec.add_dependency "view_component", ">= 3.0"
end
