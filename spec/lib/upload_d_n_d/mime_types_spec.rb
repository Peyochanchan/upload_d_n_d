# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::MimeTypes do
  describe ".resolve" do
    it "résout les nouveaux formats .ods et .heic" do
      expect(described_class.resolve([ :ods, :heic ])).to eq(
        [ "application/vnd.oasis.opendocument.spreadsheet", "image/heic" ]
      )
    end
  end

  describe ".to_extensions" do
    it "affiche les extensions des types de la table" do
      expect(described_class.to_extensions([ "image/jpeg", "image/png" ])).to eq(".jpg,.jpeg,.png")
    end

    it "affiche .ods et .heic plutôt que leur type MIME brut" do
      expect(described_class.to_extensions([
        "application/vnd.oasis.opendocument.spreadsheet",
        "image/heic"
      ])).to eq(".ods,.heic")
    end

    it "retombe sur Marcel (extension, pas type brut) pour un type absent de la table" do
      # .odp n'est pas dans la table de la gem, mais Marcel le connaît.
      result = described_class.to_extensions([ "application/vnd.oasis.opendocument.presentation" ])
      expect(result).to eq(".odp")
      expect(result).not_to include("/")
    end

    it "ne garde le type brut qu'en dernier recours (inconnu de la gem ET de Marcel)" do
      expect(described_class.to_extensions([ "application/x-totalement-inconnu" ]))
        .to eq("application/x-totalement-inconnu")
    end

    it "normalise les types MIME non standard (image/jpg -> .jpg,.jpeg)" do
      expect(described_class.to_extensions([ "image/jpg" ])).to eq(".jpg,.jpeg")
      expect(described_class.to_extensions([ "image/jpg", "image/png" ])).to eq(".jpg,.jpeg,.png")
    end
  end
end
