# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

require "rails/generators/active_record"

module UploadDND
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      desc "Installe UploadDND dans votre application Rails"

      def check_dependencies
        say "Vérification des dépendances...", :green
      end

      def add_view_component_gem
        return if gem_installed?("view_component")

        say "Ajout de view_component au Gemfile...", :yellow
        gem "view_component", "~> 3.0"

        say "N'oubliez pas de lancer 'bundle install'", :green
      end

      def add_stimulus_rails
        return if gem_installed?("stimulus-rails")

        say "Ajout de stimulus-rails au Gemfile...", :yellow
        gem "stimulus-rails"

        say "N'oubliez pas de lancer 'bundle install' puis 'rails stimulus:install'", :green
      end

      def copy_concerns
        say "Installation des concerns...", :green

        # Les concerns critiques (Uploadable, Controllers::Uploadable, FileValidator)
        # sont désormais fournis par le runtime de la gem (lib/).
        # Seul upload_authorization reste un template car il est personnalisable.
        say "  ✓ UploadDND::Uploadable         → fourni par la gem (lib/)", :cyan
        say "  ✓ UploadDND::Controllers::Uploadable → fourni par la gem (lib/)", :cyan
        say "  ✓ UploadDND::FileValidator       → fourni par la gem (lib/)", :cyan

        template "concerns/upload_authorization.rb",
                 "app/controllers/concerns/upload_d_n_d/upload_authorization.rb"

        # Nettoyage : supprime les anciennes copies si elles existent (migration depuis v0.3.x)
        remove_stale_overrides
      end

      def copy_helpers
        say "Installation des helpers...", :green

        copy_file "helpers/upload_helper.rb",
                 "app/helpers/upload_d_n_d/upload_helper.rb"
      end

      def setup_stimulus
        say "Configuration Stimulus...", :green
        say "  ✓ Controllers Stimulus → servis depuis la gem via importmap", :cyan
        say ""
        say "Ajoutez cette ligne dans votre application.js :", :yellow
        say '  import "upload_d_n_d"', :cyan
        say ""
      end

      def create_migration_file
        say "Création de la migration pour TemporaryAttachment...", :green

        migration_template "migrations/create_upload_d_n_d_temporary_attachments.rb",
                           "db/migrate/create_upload_d_n_d_temporary_attachments.rb"
      end

      def add_routes
        say "Ajout des routes...", :green

        route_content = <<~RUBY

          # Routes UploadDND
          mount UploadDND::Engine => "/upload_d_n_d"
        RUBY

        route route_content
      end

      def create_initializer
        say "Création du fichier de configuration...", :green

        template "initializers/upload_d_n_d.rb",
                 "config/initializers/upload_d_n_d.rb"
      end

      def copy_views
        # Les vues, le ViewComponent, les JS et le CSS sont servis directement depuis la gem.
        say "Assets UploadDND: servis directement depuis la gem (rien copié dans l'app).", :green
      end

      def setup_styles
        say ""
        say "🧩 Styles UploadDND", :yellow
        say "Le CSS est servi directement depuis la gem.", :cyan
        say ""
        say "Ajoutez dans votre layout :", :yellow
        say '  <%= stylesheet_link_tag "upload_d_n_d/application", media: "all" %>', :cyan
        say ""
      end

      def generate_policy_if_pundit
        if defined?(Pundit) || File.read("Gemfile").include?("pundit")
          say "Pundit détecté, génération de la policy...", :green

          if yes?("Voulez-vous générer la policy Pundit pour UploadDND ? (y/n)")
            generate "upload_d_n_d:policy"
          end
        end
      end

      def show_readme
        readme "POST_INSTALL" if File.exist?(source_paths.first + "/POST_INSTALL")
      end

      private

      # Supprime les fichiers qui étaient copiés par les anciennes versions (< 0.4.0)
      # et qui shadowent désormais le runtime de la gem.
      STALE_OVERRIDES = [
        "app/models/concerns/upload_d_n_d/uploadable.rb",
        "app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb",
        "app/validators/file_validator.rb",
        # Fichiers copiés par les versions < 0.5.0 (désormais servis depuis la gem)
        "app/javascript/controllers/upload_d_n_d/uploads_controller.js",
        "app/javascript/controllers/upload_d_n_d/preview_controller.js",
        "app/assets/stylesheets/upload_d_n_d.css",
        "app/components/upload_d_n_d/upload_component.rb",
        "app/components/upload_d_n_d/upload_component.html.erb"
      ].freeze

      def remove_stale_overrides
        stale = STALE_OVERRIDES.select { |f| File.exist?(f) }
        return if stale.empty?

        say ""
        say "⚠️  Anciennes copies détectées (désormais servies depuis la gem) :", :yellow
        stale.each { |f| say "   • #{f}", :yellow }
        say ""

        if yes?("Supprimer ces fichiers obsolètes ? (recommandé) (y/n)")
          stale.each do |f|
            remove_file f
            say "  ✓ #{f} supprimé", :green
          end
        else
          say "  ⚠️  Conservées. Attention : elles prennent priorité sur la gem.", :red
        end
        say ""
      end

      def gem_installed?(gem_name)
        File.read("Gemfile").include?(gem_name)
      rescue
        false
      end
    end
  end
end
