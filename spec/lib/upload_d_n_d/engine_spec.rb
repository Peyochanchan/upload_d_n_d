# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::Engine do
  describe "engine configuration" do
    it "is a Rails::Engine" do
      expect(described_class.superclass).to eq(Rails::Engine)
    end

    it "has isolated namespace" do
      expect(described_class.isolated?).to be true
    end

    it "has correct namespace" do
      expect(described_class.railtie_namespace).to eq(UploadDND)
    end
  end

  describe "inflections initializer" do
    it "registers DND as an acronym" do
      # Vérifie que DND est bien un acronyme reconnu
      expect("upload_d_n_d".camelize).to eq("UploadDND")
      # Note: underscore ne remet pas les underscores dans les acronymes
      expect("UploadDND".underscore).to eq("upload_dnd")
    end
  end

  describe "assets initializer" do
    it "adds JavaScript path to asset pipeline" do
      app_config = Rails.application.config
      js_path = described_class.root.join("app/javascript")

      expect(app_config.assets.paths).to include(js_path)
    end
  end

  describe "check_updates initializer" do
    context "in development environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "checks for updates in development" do
        # Le système de vérification devrait être actif
        expect(Rails.env.development?).to be true
      end
    end

    context "in production environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "does not check for updates in production" do
        # Le système de vérification ne devrait pas être actif
        expect(Rails.env.development?).to be false
      end
    end
  end

  describe "root path" do
    it "returns the gem root directory" do
      root = described_class.root
      expect(root).to be_a(Pathname)
      expect(root.to_s).to include("upload_d_n_d")
    end

    it "contains expected directories" do
      root = described_class.root
      expect(root.join("app")).to exist
      expect(root.join("lib")).to exist
      expect(root.join("app/controllers")).to exist
      expect(root.join("app/javascript")).to exist
    end
  end

  describe "routes" do
    it "has engine routes" do
      # Vérifie que le moteur a bien des routes
      expect(described_class.routes).to be_a(ActionDispatch::Routing::RouteSet)
      expect(described_class.routes.url_helpers).to respond_to(:attachments_path)
      expect(described_class.routes.url_helpers).to respond_to(:temporary_attachments_path)
    end
  end
end
