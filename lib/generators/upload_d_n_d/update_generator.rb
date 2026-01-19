# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module UploadDND
  module Generators
    class UpdateGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Met à jour les fichiers UploadDND (JS, CSS, Components) sans toucher à vos modèles"

      class_option :force,
                   type: :boolean,
                   default: false,
                   desc: "Force la mise à jour sans confirmation"

      class_option :dry_run,
                   type: :boolean,
                   default: false,
                   desc: "Affiche ce qui serait fait sans modifier les fichiers"

      def check_version
        require_relative "../../upload_d_n_d/version_tracker"

        @installed_version = UploadDND::VersionTracker.installed_version
        @current_version = UploadDND::VERSION

        say "\n📦 UploadDND Update", :cyan
        say "═" * 60, :cyan
        say "Version installée : #{@installed_version || 'inconnue'}", :yellow
        say "Version disponible: #{@current_version}", :green
        say "═" * 60, :cyan
        say ""

        unless UploadDND::VersionTracker.update_available?
          say "✓ Vous êtes déjà à jour !", :green
          exit(0)
        end
      end

      def show_outdated_files
        require_relative "../../upload_d_n_d/version_tracker"

        @outdated_files = UploadDND::VersionTracker.outdated_files

        if @outdated_files.empty?
          say "✓ Aucun fichier à mettre à jour", :green
          say ""
          say "💡 Conseil: Créez le fichier .upload_d_n_d_version pour activer le tracking", :yellow
          exit(0)
        end

        say "📝 Fichiers qui seront mis à jour:", :yellow
        say ""
        @outdated_files.each do |file|
          desc = UploadDND::VersionTracker::TRACKED_FILES[file][:description]
          say "  • #{file}", :cyan
          say "    └─ #{desc}", :light_black
        end
        say ""

        say "⚠️  Fichiers qui NE seront PAS touchés:", :yellow
        say ""
        UploadDND::VersionTracker::PRESERVED_FILES.each do |pattern|
          say "  ✓ #{pattern}", :green
        end
        say ""
      end

      def confirm_update
        return if options[:force] || options[:dry_run]

        unless yes?("Continuer avec la mise à jour ? (y/n)")
          say "Mise à jour annulée", :yellow
          exit(0)
        end
        say ""
      end

      def update_files
        require_relative "../../upload_d_n_d/version_tracker"

        say "🔄 Mise à jour des fichiers...", :green
        say ""

        @outdated_files.each do |file_path|
          file_info = UploadDND::VersionTracker::TRACKED_FILES[file_path]
          source_file = UploadDND::VersionTracker.gem_file_path(file_info[:source])

          if options[:dry_run]
            say "  [DRY RUN] Copierait: #{file_path}", :yellow
          else
            copy_file source_file, file_path, force: true
            say "  ✓ #{file_path}", :green
          end
        end

        say ""
      end

      def update_version_file
        return if options[:dry_run]

        require_relative "../../upload_d_n_d/version_tracker"

        UploadDND::VersionTracker.write_version!
        say "✓ Version mise à jour: #{UploadDND::VERSION}", :green
        say ""
      end

      def show_summary
        say "═" * 60, :cyan
        if options[:dry_run]
          say "  [DRY RUN] Aucun fichier n'a été modifié", :yellow
        else
          say "  ✅ Mise à jour terminée avec succès !", :green
        end
        say "═" * 60, :cyan
        say ""

        say "📝 Prochaines étapes:", :cyan
        say ""
        say "  1. Vérifiez que votre application démarre correctement", :white
        say "  2. Testez les fonctionnalités d'upload", :white
        say "  3. Relancez les tests: bundle exec rspec", :white
        say ""

        if @outdated_files.any? { |f| f.include?("javascript") }
          say "💡 Les fichiers JavaScript ont été modifiés.", :yellow
          say "   Si vous utilisez un bundler JS, relancez:", :yellow
          say "   • bin/rails assets:precompile (production)", :cyan
          say "   • ou redémarrez votre serveur de dev", :cyan
          say ""
        end

        unless options[:dry_run]
          say "📚 Changelog: https://github.com/votre-repo/upload_d_n_d/releases/#{UploadDND::VERSION}", :cyan
          say ""
        end
      end
    end
  end
end
