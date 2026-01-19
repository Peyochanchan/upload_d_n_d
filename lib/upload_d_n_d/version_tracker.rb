# frozen_string_literal: true

module UploadDND
  class VersionTracker
    VERSION_FILE = ".upload_d_n_d_version"

    # Fichiers qui doivent être mis à jour automatiquement
    TRACKED_FILES = {
      "app/javascript/controllers/upload_d_n_d/uploads_controller.js" => {
        source: "app/javascript/upload_d_n_d/controllers/uploads_controller.js",
        description: "Controller Stimulus principal"
      },
      "app/javascript/controllers/upload_d_n_d/preview_controller.js" => {
        source: "app/javascript/upload_d_n_d/controllers/preview_controller.js",
        description: "Controller Stimulus preview"
      },
      "app/assets/stylesheets/upload_d_n_d.css" => {
        source: "app/assets/stylesheets/upload_d_n_d/application.css",
        description: "Styles CSS (modales, dropzone, etc.)"
      },
      "app/components/upload_d_n_d/upload_component.rb" => {
        source: "app/components/upload_d_n_d/upload_component.rb",
        description: "ViewComponent Ruby"
      },
      "app/components/upload_d_n_d/upload_component.html.erb" => {
        source: "app/components/upload_d_n_d/upload_component.html.erb",
        description: "Template ViewComponent"
      }
    }.freeze

    # Fichiers à NE PAS mettre à jour automatiquement (personnalisables par l'utilisateur)
    PRESERVED_FILES = [
      "app/models/concerns/upload_d_n_d/uploadable.rb",
      "app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb",
      "app/helpers/upload_d_n_d/upload_helper.rb",
      "config/initializers/upload_d_n_d.rb",
      "app/models/**/*.rb" # Modèles utilisateur
    ].freeze

    class << self
      # Récupère la version installée dans l'app
      def installed_version
        version_file_path = Rails.root.join(VERSION_FILE)
        return nil unless File.exist?(version_file_path)

        File.read(version_file_path).strip
      end

      # Écrit la version actuelle de la gem dans l'app
      def write_version!
        File.write(Rails.root.join(VERSION_FILE), UploadDND::VERSION)
      end

      # Vérifie si une mise à jour est nécessaire
      def update_available?
        installed = installed_version
        return true if installed.nil? # Pas de version = jamais installé

        Gem::Version.new(UploadDND::VERSION) > Gem::Version.new(installed)
      rescue ArgumentError
        true # En cas d'erreur de parsing, proposer la mise à jour
      end

      # Liste les fichiers qui ont besoin d'être mis à jour
      def outdated_files
        return [] unless update_available?

        TRACKED_FILES.keys.select do |file_path|
          app_file = Rails.root.join(file_path)
          next false unless File.exist?(app_file)

          # Compare les checksums
          app_checksum = Digest::MD5.file(app_file).hexdigest
          gem_file = gem_file_path(TRACKED_FILES[file_path][:source])
          next false unless File.exist?(gem_file)

          gem_checksum = Digest::MD5.file(gem_file).hexdigest
          app_checksum != gem_checksum
        end
      end

      # Récupère le chemin complet d'un fichier dans la gem
      def gem_file_path(relative_path)
        gem_root = Gem::Specification.find_by_name("upload_d_n_d").gem_dir
        File.join(gem_root, relative_path)
      rescue Gem::MissingSpecError
        # En développement local, on est dans le repo de la gem
        File.expand_path("../../#{relative_path}", __dir__)
      end

      # Message de notification pour le démarrage Rails
      def update_notice
        return nil unless update_available?

        outdated = outdated_files
        return nil if outdated.empty?

        <<~MSG

          ╔════════════════════════════════════════════════════════════════╗
          ║  📦 UploadDND - Mise à jour disponible                         ║
          ╠════════════════════════════════════════════════════════════════╣
          ║  Version installée : #{installed_version.to_s.ljust(43)} ║
          ║  Version disponible: #{UploadDND::VERSION.ljust(43)} ║
          ║                                                                ║
          ║  Fichiers obsolètes: #{outdated.size.to_s.ljust(44)} ║
          #{outdated.map { |f| "║  • #{File.basename(f).ljust(60)} ║" }.join("\n")}
          ║                                                                ║
          ║  Pour mettre à jour (recommandé):                             ║
          ║  $ rails g upload_d_n_d:update                                ║
          ║                                                                ║
          ║  ⚠️  Vos modèles et configurations seront préservés            ║
          ╚════════════════════════════════════════════════════════════════╝

        MSG
      end
    end
  end
end
