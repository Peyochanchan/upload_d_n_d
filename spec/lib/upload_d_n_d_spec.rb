# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND do
  describe ".VERSION" do
    it "has a version number" do
      expect(UploadDND::VERSION).not_to be nil
      expect(UploadDND::VERSION).to be_a(String)
      expect(UploadDND::VERSION).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(UploadDND.configuration).to be_a(UploadDND::Configuration)
    end

    it "caches the configuration instance" do
      config1 = UploadDND.configuration
      config2 = UploadDND.configuration
      expect(config1).to equal(config2)
    end
  end

  describe ".configure" do
    after do
      # Reset configuration after each test
      UploadDND.reset_configuration!
    end

    it "yields the configuration" do
      expect { |b| UploadDND.configure(&b) }.to yield_with_args(UploadDND.configuration)
    end

    it "allows setting configuration values" do
      UploadDND.configure do |config|
        config.max_size = 50.megabytes
        config.main_color = "#FF0000"
      end

      expect(UploadDND.configuration.max_size).to eq(50.megabytes)
      expect(UploadDND.configuration.main_color).to eq("#FF0000")
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      UploadDND.configure do |config|
        config.max_size = 999.megabytes
      end

      UploadDND.reset_configuration!

      expect(UploadDND.configuration.max_size).to eq(10.megabytes)
    end
  end

  describe "constants" do
    it "defines Configuration class" do
      expect(defined?(UploadDND::Configuration)).to be_truthy
    end

    it "defines Engine class" do
      expect(defined?(UploadDND::Engine)).to be_truthy
    end

    # VersionTracker is loaded on-demand by Engine, not autoloaded

    it "defines FileValidator class" do
      expect(defined?(UploadDND::FileValidator)).to be_truthy
    end

    it "defines Uploadable module" do
      expect(defined?(UploadDND::Uploadable)).to be_truthy
    end

    it "defines Controllers::Uploadable module" do
      expect(defined?(UploadDND::Controllers::Uploadable)).to be_truthy
    end

    it "defines TemporaryAttachment model" do
      expect(defined?(UploadDND::TemporaryAttachment)).to be_truthy
    end
  end

  describe "autoloading" do
    it "autoloads Configuration" do
      expect(UploadDND::Configuration).to be_a(Class)
    end

    it "autoloads FileValidator" do
      expect(UploadDND::FileValidator).to be_a(Class)
    end

    it "autoloads Uploadable" do
      expect(UploadDND::Uploadable).to be_a(Module)
    end
  end
end
