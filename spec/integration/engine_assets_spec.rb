# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Engine assets served from gem", type: :integration do
  let(:engine_root) { UploadDND::Engine.root }

  describe "JavaScript controllers" do
    it "serves uploads_controller.js from the gem" do
      path = engine_root.join("app/javascript/upload_d_n_d/controllers/uploads_controller.js")
      expect(File.exist?(path)).to be true
    end

    it "serves preview_controller.js from the gem" do
      path = engine_root.join("app/javascript/upload_d_n_d/controllers/preview_controller.js")
      expect(File.exist?(path)).to be true
    end

    it "has an index.js entry point that auto-registers controllers" do
      path = engine_root.join("app/javascript/upload_d_n_d/index.js")
      expect(File.exist?(path)).to be true

      content = File.read(path)
      expect(content).to include('application.register("upload-d-n-d--uploads"')
      expect(content).to include('application.register("upload-d-n-d--preview"')
    end
  end

  describe "CSS" do
    it "serves application.css from the gem" do
      path = engine_root.join("app/assets/stylesheets/upload_d_n_d/application.css")
      expect(File.exist?(path)).to be true
    end

    it "stylesheets path is in the asset pipeline" do
      css_path = engine_root.join("app/assets/stylesheets")
      expect(Rails.application.config.assets.paths).to include(css_path)
    end
  end

  describe "ViewComponent" do
    it "serves upload_component.rb from the gem" do
      path = engine_root.join("app/components/upload_d_n_d/upload_component.rb")
      expect(File.exist?(path)).to be true
    end

    it "serves upload_component.html.erb from the gem" do
      path = engine_root.join("app/components/upload_d_n_d/upload_component.html.erb")
      expect(File.exist?(path)).to be true
    end

    it "UploadComponent is loadable from the gem" do
      expect(UploadDND::UploadComponent).to be_a(Class)
      expect(UploadDND::UploadComponent.ancestors).to include(ViewComponent::Base)
    end
  end

  describe "importmap configuration" do
    it "has an importmap config file" do
      path = engine_root.join("config/importmap.rb")
      expect(File.exist?(path)).to be true
    end

    it "pins upload_d_n_d as main entry point" do
      content = File.read(engine_root.join("config/importmap.rb"))
      expect(content).to include('pin "upload_d_n_d"')
    end

    it "pins individual controllers" do
      content = File.read(engine_root.join("config/importmap.rb"))
      expect(content).to include("pin_all_from")
      expect(content).to include("upload_d_n_d/controllers")
    end
  end

  describe "no files should be copied to host app" do
    it "does not require version tracking" do
      expect(defined?(UploadDND::VersionTracker)).to be_falsey
    end

    it "does not have an update generator" do
      update_generator_path = engine_root.join("lib/generators/upload_d_n_d/update_generator.rb")
      expect(File.exist?(update_generator_path)).to be false
    end

    it "does not have a version_tracker" do
      version_tracker_path = engine_root.join("lib/upload_d_n_d/version_tracker.rb")
      expect(File.exist?(version_tracker_path)).to be false
    end
  end
end
