# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require_relative "mime_type_helper"

module UploadDND
  module Generators
    class ModelGenerator < Rails::Generators::NamedBase
      include MimeTypeHelper

      source_root File.expand_path("templates", __dir__)

      desc "Configure un modèle pour utiliser UploadDND avec drag & drop"

      class_option :attribute,
                   type: :string,
                   aliases: "-a",
                   desc: "Nom de l'attribut uploadable (ex: avatar, documents)",
                   required: true

      class_option :multiple,
                   type: :boolean,
                   default: false,
                   desc: "Upload multiple fichiers (has_many_attached)"

      class_option :content_type,
                   type: :array,
                   default: [ "jpg", "png" ],
                   desc: "Extensions de fichiers acceptées (ex: jpg png pdf) ou MIME types"

      class_option :max_size,
                   type: :string,
                   default: "5",
                   desc: "Taille max en MB"

      class_option :max_files,
                   type: :string,
                   default: nil,
                   desc: "Nombre max de fichiers (pour multiple)"

      class_option :controller,
                   type: :boolean,
                   default: true,
                   desc: "Générer/mettre à jour le controller"

      class_option :views,
                   type: :boolean,
                   default: true,
                   desc: "Générer/mettre à jour les vues"

      def validate_options
        unless options[:attribute].present?
          say "❌ L'option --attribute est requise", :red
          say "Exemple: rails g upload_d_n_d:model User --attribute=avatar", :yellow
          exit(1)
        end
      end

      def check_model_exists
        unless model_exists?
          say "❌ Le modèle #{model_path} n'existe pas", :red
          say "Créez d'abord le modèle avec: rails g model #{class_name}", :yellow
          exit(1)
        end
      end

      def add_uploadable_to_model
        say "📝 Configuration du modèle (instructions)", :green

        model_content = File.read(model_path)

        already_has_concern = model_content.include?("include UploadDND::Uploadable")
        association_type = options[:multiple] ? "has_many_attached" : "has_one_attached"
        already_has_association = model_content.match?(/#{association_type}\s+:#{attribute_name}/)
        already_has_uploadable = model_content.match?(/uploadable\s+:#{attribute_name}/)

        if already_has_concern && already_has_association && already_has_uploadable
          say "  ✓ Le modèle semble déjà configuré pour :#{attribute_name}", :yellow
          return
        end

        say "Ajoutez (ou vérifiez) ces lignes dans #{model_path} :", :yellow
        say ""

        unless already_has_concern
          say "  include UploadDND::Uploadable", :cyan
        end
        unless already_has_association
          say "  #{association_type} :#{attribute_name}", :cyan
        end
        unless already_has_uploadable
          uploadable_attribute_code.each_line { |l| say l.rstrip, :cyan }
        end

        say ""
      end

      def add_active_storage_association
        # Non-invasif: inclus dans add_uploadable_to_model (instructions), on garde la méthode
        # pour compatibilité de flow / messages.
      end

      def update_controller
        return unless options[:controller]

        if controller_exists?
          say "🎮 Controller existant détecté (instructions)", :green
          show_controller_instructions
        else
          say "🎮 Génération du controller...", :green
          generate_controller
        end
      end

      def add_routes_for_uploads
        say "🛣️  Routes (instructions)", :green

        say "Ajoutez ces routes dans config/routes.rb (dans le bon scope/namespace) :", :yellow
        say ""

        if namespaced?
          say "  # Exemple si votre ressource est dans un namespace (adaptez au vôtre)", :cyan
          say "  namespace :#{namespace_path.underscore} do", :cyan
          say "    resources :#{plural_name} do", :cyan
          say "      member do", :cyan
          say "        post :attach_file", :cyan
          say "        delete :remove_file", :cyan
          say "      end", :cyan
          say "    end", :cyan
          say "  end", :cyan
        else
          say "  resources :#{plural_name} do", :cyan
          say "    member do", :cyan
          say "      post :attach_file", :cyan
          say "      delete :remove_file", :cyan
          say "    end", :cyan
          say "  end", :cyan
        end

        say ""
      end

      def update_views
        return unless options[:views]

        say "👁️  Génération des vues...", :green
        create_form_partial
        create_show_partial
      end

      def add_uploadable_concern_to_controller
        # Non-invasif: on n'injecte plus dans les controllers existants.
      end

      def add_actions_to_before_action
        # Non-invasif: instructions via show_controller_instructions
      end

      def show_summary
        extensions = normalized_content_types
        mime_types = convert_to_mime_types(extensions)

        say "\n✅ Configuration terminée!", :green
        say "\n📋 Résumé:", :cyan
        say "  Modèle: #{class_name}"
        say "  Namespace: #{namespace_path}" if namespaced?
        say "  Attribut: #{attribute_name}"
        say "  Type: #{options[:multiple] ? 'has_many_attached' : 'has_one_attached'}"
        say "  Extensions: #{extensions.join(', ')}"
        say "  MIME types: #{mime_types.join(', ')}"
        say "  Taille max: #{options[:max_size]}MB"
        say "  Fichiers max: #{options[:max_files]}" if options[:max_files]

        say "\n📝 Prochaines étapes:", :yellow
        say "  1. Copiez/collez les snippets affichés (modèle/routes/controller si applicable)"
        say "  2. Lancez la migration si nécessaire: rails db:migrate"
        say "  3. Vérifiez #{model_path}"
        say "  4. Vérifiez #{controller_path}" if options[:controller]
        say "  5. Vérifiez les vues dans #{views_path}" if options[:views]
        say "\n💡 Utilisez dans vos vues:", :cyan
        say "  <%= upload_field :#{attribute_name}, record: @#{singular_name} %>"
      end

      private

      def model_exists?
        File.exist?(model_path)
      end

      def controller_exists?
        File.exist?(controller_path)
      end

      def model_path
        @model_path ||= File.join("app/models", "#{file_path}.rb")
      end

      def controller_path
        @controller_path ||= File.join("app/controllers", namespace_path, "#{plural_name}_controller.rb")
      end

      def views_path
        @views_path ||= File.join("app/views", namespace_path, plural_name)
      end

      def namespace_path
        @namespace_path ||= class_path.join("/")
      end


      def model_class_name
        class_name.split("::").last
      end

      def attribute_name
        options[:attribute]
      end

      def singular_name
        file_name.split("/").last
      end

      def uploadable_attribute_code
        max_files_option = options[:max_files] ? ", max_files: #{options[:max_files]}" : ""

        # Convertit les extensions en MIME types
        mime_types = convert_to_mime_types(normalized_content_types)

        <<~RUBY.indent(2)

          uploadable :#{attribute_name},
                     content_type: #{mime_types.inspect},
                     max_size: #{options[:max_size]}.megabytes#{max_files_option}
        RUBY
      end

      def active_storage_code
        association_type = options[:multiple] ? "has_many_attached" : "has_one_attached"

        <<~RUBY.indent(2)

          #{association_type} :#{attribute_name}
        RUBY
      end

      def update_existing_controller
        # Non-invasif: on ne modifie plus le controller existant.
      end

      def generate_controller
        # Génère un controller basique si il n'existe pas
        template "controller.rb.tt", controller_path
      end

      def create_form_partial
        # On ne crée pas le partial s'il existe déjà pour ne pas écraser les formulaires existants
        if File.exist?(File.join(views_path, "_form.html.erb"))
           say "  ⚠️  Le formulaire existe déjà, ajout manuel requis", :yellow
           say "  Ajoutez ce code dans votre formulaire :", :cyan
           say ""
           say "    <%= upload_field :#{attribute_name}, record: @#{singular_name} %>", :cyan
           say ""
        else
          template "views/_form.html.erb.tt", File.join(views_path, "_form.html.erb")
        end
      end

      def create_show_partial
        uploads_file = File.join(views_path, "_uploads.html.erb")

        if File.exist?(uploads_file)
          say "  ⚠️  Le partial _uploads.html.erb existe déjà (instructions)", :yellow
          say "  Ajoutez manuellement cette section pour :#{attribute_name} :", :cyan
          say ""
          generate_upload_section_code.each_line { |l| say l.rstrip, :cyan }
          say ""
        else
          say "  → Création de _uploads.html.erb", :green
          template "views/_uploads.html.erb.tt", uploads_file
        end
      end

      def show_controller_instructions
        say "Ajoutez (ou vérifiez) ces éléments dans #{controller_path} :", :yellow
        say ""
        say "  include UploadDND::Controllers::Uploadable", :cyan
        say ""
        say "  # Assurez-vous que votre before_action charge le record pour :attach_file et :remove_file", :cyan
        say "  # Exemple:", :cyan
        say "  # before_action :set_#{singular_name}, only: [:show, :edit, :update, :destroy, :attach_file, :remove_file]", :cyan
        say ""
        say "  # Support upload temporaire (dans create) :", :cyan
        say "  # @#{singular_name}.temp_upload_session_id = params[:temp_upload_session_id] if params[:temp_upload_session_id] == session.id.to_s", :cyan
        say ""
      end

      # Accepte:
      # - --content_type=pdf docx pptx
      # - --content_type=pdf,docx,pptx
      # - mixte (espaces + virgules)
      def normalized_content_types
        Array(options[:content_type])
          .flat_map { |v| v.to_s.split(/[,\s]+/) }
          .map(&:strip)
          .reject(&:empty?)
          .uniq
      end

      def generate_upload_section_code
        if options[:multiple]
          <<~ERB

          <div class="uploads-section">
            <h3>#{attribute_name.to_s.humanize}</h3>

            <% if @#{singular_name}.#{attribute_name}.attached? %>
              <%# Multiple fichiers %>
              <ul class="uploaded-files">
                <% @#{singular_name}.#{attribute_name}.each do |file| %>
                  <li>
                    <% if file.image? %>
                      <%= image_tag file.variant(resize_to_limit: [200, 200]), alt: file.filename.to_s %>
                    <% else %>
                      <i class="file-icon <%= file_icon_class(file.filename.to_s) %>"></i>
                    <% end %>
                    <span><%= link_to file.filename, rails_blob_path(file, disposition: "attachment") %></span>
                    <span class="file-size"><%= number_to_human_size(file.byte_size) %></span>
                  </li>
                <% end %>
              </ul>
            <% else %>
              <p class="no-uploads">Aucun fichier uploadé</p>
            <% end %>
          </div>
          ERB
        else
          <<~ERB

          <div class="uploads-section">
            <h3>#{attribute_name.to_s.humanize}</h3>

            <% if @#{singular_name}.#{attribute_name}.attached? %>
              <%# Un seul fichier %>
              <div class="uploaded-file">
                <% if @#{singular_name}.#{attribute_name}.image? %>
                  <%= image_tag @#{singular_name}.#{attribute_name}.variant(resize_to_limit: [400, 400]), alt: @#{singular_name}.#{attribute_name}.filename.to_s %>
                <% else %>
                  <i class="file-icon <%= file_icon_class(@#{singular_name}.#{attribute_name}.filename.to_s) %>"></i>
                <% end %>
                <p>
                  <%= link_to @#{singular_name}.#{attribute_name}.filename, rails_blob_path(@#{singular_name}.#{attribute_name}, disposition: "attachment") %>
                  <span class="file-size"><%= number_to_human_size(@#{singular_name}.#{attribute_name}.byte_size) %></span>
                </p>
              </div>
            <% else %>
              <p class="no-uploads">Aucun fichier uploadé</p>
            <% end %>
          </div>
          ERB
        end
      end
    end
  end
end
