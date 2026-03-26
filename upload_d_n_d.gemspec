require_relative "lib/upload_d_n_d/version"

Gem::Specification.new do |spec|
  spec.name        = "upload_d_n_d"
  spec.version     = UploadDND::VERSION
  spec.authors     = [ "Pierre Cherbero" ]
  spec.email       = [ "cameleon24@outlook.fr" ]
  spec.homepage    = "https://github.com/Peyochanchan/upload_d_n_d"
  spec.summary     = "Système de drag & drop sécurisé pour Rails avec ActiveStorage"
  spec.description = "UploadDND fournit une interface drag & drop élégante et sécurisée pour vos uploads de fichiers dans Rails. Basé sur ActiveStorage, Stimulus et ViewComponent, il offre une validation serveur robuste, un support d'upload temporaire, et une intégration facile avec Pundit/CanCanCan."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Peyochanchan/upload_d_n_d"
  spec.metadata["changelog_uri"] = "https://github.com/Peyochanchan/upload_d_n_d/blob/main/docs/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/Peyochanchan/upload_d_n_d/issues"
  spec.metadata["documentation_uri"] = "https://github.com/Peyochanchan/upload_d_n_d/blob/main/README.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.2.3"

  # Dépendance optionnelle pour le rate limiting
  spec.add_development_dependency "rack-attack", "~> 6.7"
end
