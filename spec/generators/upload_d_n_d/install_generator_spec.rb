# frozen_string_literal: true

require "rails_helper"
require "generators/upload_d_n_d/install_generator"

RSpec.describe UploadDND::Generators::InstallGenerator, type: :generator do
  let(:destination_root) { Rails.root }

  describe "STALE_OVERRIDES" do
    let(:stale_overrides) { described_class.const_get(:STALE_OVERRIDES) }

    it "includes stale concern copies" do
      expect(stale_overrides).to include(
        "app/models/concerns/upload_d_n_d/uploadable.rb",
        "app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb",
        "app/controllers/concerns/upload_d_n_d/upload_authorization.rb"
      )
    end

    it "does not treat the host app's own FileValidator as stale" do
      expect(stale_overrides).not_to include("app/validators/file_validator.rb")
    end

    it "includes pre-0.5.0 stale files (JS, CSS, Component)" do
      expect(stale_overrides).to include(
        "app/javascript/controllers/upload_d_n_d/uploads_controller.js",
        "app/javascript/controllers/upload_d_n_d/preview_controller.js",
        "app/assets/stylesheets/upload_d_n_d.css",
        "app/components/upload_d_n_d/upload_component.rb",
        "app/components/upload_d_n_d/upload_component.html.erb"
      )
    end
  end

  describe "generator methods" do
    let(:generator) { described_class.new([], {}, { destination_root: destination_root }) }

    describe "no file copying for JS, CSS, or Component" do
      it "does not define install_stimulus_controller method" do
        expect(generator).not_to respond_to(:install_stimulus_controller)
      end

      it "does not define copy_styles method" do
        expect(generator).not_to respond_to(:copy_styles)
      end

      it "does not define copy_component method" do
        expect(generator).not_to respond_to(:copy_component)
      end

      it "does not define create_version_file method" do
        expect(generator).not_to respond_to(:create_version_file)
      end

      it "does not define register_stimulus_controller method" do
        expect(generator).not_to respond_to(:register_stimulus_controller)
      end
    end

    describe "methods that should exist" do
      it "defines setup_stimulus (informational only)" do
        expect(generator).to respond_to(:setup_stimulus)
      end

      it "defines setup_styles (informational only)" do
        expect(generator).to respond_to(:setup_styles)
      end

      it "defines copy_concerns" do
        expect(generator).to respond_to(:copy_concerns)
      end

      it "defines copy_helpers" do
        expect(generator).to respond_to(:copy_helpers)
      end

      it "defines create_migration_file" do
        expect(generator).to respond_to(:create_migration_file)
      end

      it "defines create_initializer" do
        expect(generator).to respond_to(:create_initializer)
      end

      it "defines add_routes" do
        expect(generator).to respond_to(:add_routes)
      end
    end
  end

  describe "templates" do
    let(:templates_path) { File.expand_path("../../../lib/generators/upload_d_n_d/templates", __dir__) }

    it "no longer ships the dead authorization concern template" do
      expect(File.exist?(File.join(templates_path, "concerns/upload_authorization.rb"))).to be false
    end

    it "has the helper template" do
      expect(File.exist?(File.join(templates_path, "helpers/upload_helper.rb"))).to be true
    end

    it "has the initializer template" do
      expect(File.exist?(File.join(templates_path, "initializers/upload_d_n_d.rb"))).to be true
    end

    it "has the migration template" do
      expect(File.exist?(File.join(templates_path, "migrations/create_upload_d_n_d_temporary_attachments.rb"))).to be true
    end

    it "has the POST_INSTALL readme" do
      expect(File.exist?(File.join(templates_path, "POST_INSTALL"))).to be true
    end

    it "POST_INSTALL references v0.5.0 architecture" do
      content = File.read(File.join(templates_path, "POST_INSTALL"))
      expect(content).to include('import "upload_d_n_d"')
      expect(content).to include("upload_d_n_d/application")
      expect(content).not_to include("stimulus:manifest:update")
      expect(content).not_to include("upload_d_n_d:update")
    end
  end
end
