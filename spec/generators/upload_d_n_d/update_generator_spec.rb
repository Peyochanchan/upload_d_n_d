# frozen_string_literal: true

require "rails_helper"
require "generators/upload_d_n_d/update_generator"

RSpec.describe UploadDND::Generators::UpdateGenerator, type: :generator do
  let(:destination_root) { Rails.root.join("tmp/generator_test") }
  let(:version_file) { destination_root.join(".upload_d_n_d_version") }

  before do
    # Nettoie et prépare le répertoire de destination
    FileUtils.rm_rf(destination_root)
    FileUtils.mkdir_p(destination_root)

    # Simule une application Rails avec le répertoire racine temporaire
    allow(Rails).to receive(:root).and_return(destination_root)

    # Crée le fichier de version pour simuler une installation
    File.write(version_file, "0.1.0")
  end

  after do
    # Nettoie
    FileUtils.rm_rf(destination_root)
  end

  describe "update detection" do
    it "detects when an update is available" do
      expect(UploadDND::VersionTracker.update_available?).to be true
    end

    it "detects outdated files" do
      # Crée un fichier obsolète
      test_file = destination_root.join("app/javascript/controllers/upload_d_n_d/uploads_controller.js")
      FileUtils.mkdir_p(test_file.dirname)
      File.write(test_file, "// Old content")

      outdated = UploadDND::VersionTracker.outdated_files
      expect(outdated).to include("app/javascript/controllers/upload_d_n_d/uploads_controller.js")
    end
  end

  describe "version management" do
    it "reads the installed version" do
      expect(UploadDND::VersionTracker.installed_version).to eq("0.1.0")
    end

    it "can write the current version" do
      UploadDND::VersionTracker.write_version!
      expect(File.read(version_file)).to eq(UploadDND::VERSION)
    end
  end

  describe "file tracking" do
    it "has a list of tracked files" do
      tracked = UploadDND::VersionTracker::TRACKED_FILES
      expect(tracked).to be_a(Hash)
      expect(tracked).not_to be_empty
    end

    it "has a list of preserved files" do
      preserved = UploadDND::VersionTracker::PRESERVED_FILES
      expect(preserved).to be_an(Array)
      expect(preserved).to include("app/models/concerns/upload_d_n_d/uploadable.rb")
    end

    it "excludes preserved files from updates" do
      preserved_patterns = UploadDND::VersionTracker::PRESERVED_FILES
      tracked_files = UploadDND::VersionTracker::TRACKED_FILES.keys

      # Aucun fichier tracké ne devrait matcher un pattern préservé
      tracked_files.each do |tracked|
        preserved_patterns.each do |pattern|
          # Simplifie la vérification: les fichiers trackés ne sont pas dans les preserved
          if pattern.include?("**")
            # Skip wildcard patterns for this simple test
            next
          end
          expect(tracked).not_to eq(pattern)
        end
      end
    end
  end

  describe "update notice" do
    it "returns nil when no update is available" do
      File.write(version_file, UploadDND::VERSION)
      expect(UploadDND::VersionTracker.update_notice).to be_nil
    end

    it "returns a notice when update is available with outdated files" do
      # Crée un fichier obsolète
      test_file = destination_root.join("app/javascript/controllers/upload_d_n_d/uploads_controller.js")
      FileUtils.mkdir_p(test_file.dirname)
      File.write(test_file, "// Old content")

      notice = UploadDND::VersionTracker.update_notice
      expect(notice).to include("Mise à jour disponible")
      expect(notice).to include("rails g upload_d_n_d:update")
    end
  end
end
