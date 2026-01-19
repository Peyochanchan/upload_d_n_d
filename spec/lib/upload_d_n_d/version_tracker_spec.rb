# frozen_string_literal: true

require "rails_helper"
require_relative "../../../lib/upload_d_n_d/version_tracker"

RSpec.describe UploadDND::VersionTracker do
  let(:version_file_path) { Rails.root.join(".upload_d_n_d_version") }

  before do
    # Nettoie le fichier de version avant chaque test
    FileUtils.rm_f(version_file_path)
  end

  after do
    # Nettoie après chaque test
    FileUtils.rm_f(version_file_path)
  end

  describe ".installed_version" do
    context "when version file exists" do
      it "returns the installed version" do
        File.write(version_file_path, "0.1.0")
        expect(described_class.installed_version).to eq("0.1.0")
      end

      it "strips whitespace from version" do
        File.write(version_file_path, "  0.2.0  \n")
        expect(described_class.installed_version).to eq("0.2.0")
      end
    end

    context "when version file does not exist" do
      it "returns nil" do
        expect(described_class.installed_version).to be_nil
      end
    end
  end

  describe ".write_version!" do
    it "writes the current VERSION to file" do
      described_class.write_version!
      expect(File.read(version_file_path)).to eq(UploadDND::VERSION)
    end

    it "overwrites existing version" do
      File.write(version_file_path, "0.0.1")
      described_class.write_version!
      expect(File.read(version_file_path)).to eq(UploadDND::VERSION)
    end
  end

  describe ".update_available?" do
    context "when no version file exists" do
      it "returns true (needs initial installation)" do
        expect(described_class.update_available?).to be true
      end
    end

    context "when installed version is older" do
      it "returns true" do
        File.write(version_file_path, "0.1.0")
        expect(described_class.update_available?).to be true
      end
    end

    context "when installed version is current" do
      it "returns false" do
        File.write(version_file_path, UploadDND::VERSION)
        expect(described_class.update_available?).to be false
      end
    end

    context "when installed version is newer (downgrade scenario)" do
      it "returns false" do
        File.write(version_file_path, "99.99.99")
        expect(described_class.update_available?).to be false
      end
    end
  end

  describe ".gem_file_path" do
    it "returns the full path to a gem file" do
      path = described_class.gem_file_path("app/javascript/upload_d_n_d/controllers/uploads_controller.js")
      expect(path.to_s).to include("upload_d_n_d")
      expect(path.to_s).to include("uploads_controller.js")
      expect(File.exist?(path)).to be true
    end
  end

  describe ".outdated_files" do
    let(:test_js_file) { Rails.root.join("app/javascript/controllers/upload_d_n_d/uploads_controller.js") }

    before do
      # Crée le répertoire si nécessaire
      FileUtils.mkdir_p(test_js_file.dirname)
    end

    after do
      # Nettoie
      FileUtils.rm_f(test_js_file) if File.exist?(test_js_file)
    end

    context "when tracked file does not exist in app" do
      it "does not include it in outdated files" do
        FileUtils.rm_f(test_js_file)
        expect(described_class.outdated_files).not_to include(test_js_file.to_s)
      end
    end

    context "when tracked file exists and is identical to gem" do
      it "does not include it in outdated files" do
        gem_file = described_class.gem_file_path("app/javascript/upload_d_n_d/controllers/uploads_controller.js")
        FileUtils.cp(gem_file, test_js_file)

        outdated = described_class.outdated_files
        expect(outdated).not_to include("app/javascript/controllers/upload_d_n_d/uploads_controller.js")
      end
    end

    context "when tracked file exists and is different from gem" do
      it "includes it in outdated files" do
        # Écrit un contenu différent
        File.write(test_js_file, "// Modified content")

        outdated = described_class.outdated_files
        expect(outdated).to include("app/javascript/controllers/upload_d_n_d/uploads_controller.js")
      end
    end
  end

  describe ".update_notice" do
    let(:test_js_file) { Rails.root.join("app/javascript/controllers/upload_d_n_d/uploads_controller.js") }

    before do
      FileUtils.mkdir_p(test_js_file.dirname)
      File.write(version_file_path, "0.1.0")
    end

    after do
      FileUtils.rm_f(test_js_file) if File.exist?(test_js_file)
    end

    context "when no update is available" do
      it "returns nil" do
        File.write(version_file_path, UploadDND::VERSION)
        expect(described_class.update_notice).to be_nil
      end
    end

    context "when update is available but no files are outdated" do
      it "returns nil" do
        expect(described_class.update_notice).to be_nil
      end
    end

    context "when update is available with outdated files" do
      it "returns formatted notice with version info" do
        # Crée un fichier obsolète
        File.write(test_js_file, "// Old content")

        notice = described_class.update_notice
        expect(notice).to include("📦 UploadDND - Mise à jour disponible")
        expect(notice).to include("Version installée : 0.1.0")
        expect(notice).to include("Version disponible: #{UploadDND::VERSION}")
        expect(notice).to include("rails g upload_d_n_d:update")
      end

      it "includes list of outdated files" do
        File.write(test_js_file, "// Old content")

        notice = described_class.update_notice
        expect(notice).to include("uploads_controller.js")
      end

      it "shows correct count of outdated files" do
        File.write(test_js_file, "// Old content")

        notice = described_class.update_notice
        expect(notice).to match(/Fichiers obsolètes:\s+\d+/)
      end
    end
  end

  describe "TRACKED_FILES constant" do
    it "contains all expected tracked files" do
      expect(described_class::TRACKED_FILES.keys).to include(
        "app/javascript/controllers/upload_d_n_d/uploads_controller.js",
        "app/javascript/controllers/upload_d_n_d/preview_controller.js",
        "app/assets/stylesheets/upload_d_n_d.css",
        "app/components/upload_d_n_d/upload_component.rb",
        "app/components/upload_d_n_d/upload_component.html.erb"
      )
    end

    it "has source and description for each tracked file" do
      described_class::TRACKED_FILES.each do |_path, info|
        expect(info).to have_key(:source)
        expect(info).to have_key(:description)
        expect(info[:source]).to be_a(String)
        expect(info[:description]).to be_a(String)
      end
    end
  end

  describe "PRESERVED_FILES constant" do
    it "contains patterns for files that should never be touched" do
      expect(described_class::PRESERVED_FILES).to include(
        "app/models/concerns/upload_d_n_d/uploadable.rb",
        "app/controllers/concerns/upload_d_n_d/controllers/uploadable.rb",
        "app/helpers/upload_d_n_d/upload_helper.rb",
        "config/initializers/upload_d_n_d.rb"
      )
    end

    it "includes wildcard for user models" do
      expect(described_class::PRESERVED_FILES).to include("app/models/**/*.rb")
    end
  end
end
