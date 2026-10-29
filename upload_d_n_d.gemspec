require_relative "lib/upload_d_n_d/version"

Gem::Specification.new do |spec|
  spec.name        = "upload_d_n_d"
  spec.version     = UploadDND::VERSION
  spec.authors     = [ "Pierre Cherbero" ]
  spec.email       = [ "cameleon24@outlook.fr" ]
  spec.summary     = "Secure drag & drop file uploads for Rails, built on ActiveStorage"
  spec.description = "UploadDND provides a drag & drop upload interface for Rails apps, built on ActiveStorage, Stimulus and ViewComponent. It validates files server-side (MIME sniffing, size, count), supports temporary uploads for new records, and authorizes every request fail-closed through Pundit or CanCanCan."
  spec.license     = "MIT"

  spec.homepage    = "https://github.com/Peyochanchan/upload_d_n_d"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/docs/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "docs/CHANGELOG.md", "package.json"]
  end

  # Testé sur Rails 8.1. La borne haute < 8.2 doit être relâchée (et une version
  # publiée) avant qu'une app hôte monte en Rails 8.2.
  spec.add_dependency "rails", ">= 7.2.3", "< 8.2"
  spec.add_dependency "view_component", ">= 3.0"
end
