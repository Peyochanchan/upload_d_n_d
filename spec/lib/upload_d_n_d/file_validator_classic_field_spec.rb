# frozen_string_literal: true

require "rails_helper"
require "tempfile"

# Parcours « champ fichier classique » : le fichier part avec le formulaire et
# n'est envoyé au stockage qu'après le `save`. À la validation, le blob n'est
# pas encore sur le stockage. Avant le correctif, `strict_mime_check` lisait
# `file.download` → `ActiveStorage::FileNotFoundError` → tous les fichiers
# refusés par erreur. Ces specs utilisent de vrais modèles ActiveStorage (pas
# de mock) pour exercer `record.attachment_changes`.
RSpec.describe UploadDND::FileValidator, "avec un champ fichier classique" do
  # Un PDF et un PNG minimaux, reconnus par Marcel sur leur contenu réel.
  let(:pdf_bytes) { "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n".b }
  let(:png_bytes) { "\x89PNG\r\n\x1a\n".b + ("\x00" * 64).b }

  # UploadedFile adossé à un vrai tempfile, comme un envoi multipart.
  def uploaded(content, filename:, type:)
    file = Tempfile.new([ "upload", File.extname(filename) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file, type, original_filename: filename)
  end

  describe "has_one_attached + strict_mime_check" do
    before do
      stub_const(
        "ClassicDocUser",
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          has_one_attached :classic_doc
          validates :classic_doc, file: { content_type: [ "application/pdf" ], strict_mime_check: true }
        end
      )
    end

    it "accepte un vrai PDF sans FileNotFoundError et persiste le fichier" do
      user = ClassicDocUser.new
      user.classic_doc = uploaded(pdf_bytes, filename: "avenant.pdf", type: "application/pdf")

      expect(user).to be_valid
      expect(user.save).to be(true)
      expect(user.reload.classic_doc).to be_attached
    end

    it "refuse un fichier au type usurpé avec l'erreur d'usurpation, pas « détection impossible »" do
      user = ClassicDocUser.new
      # Contenu PNG, mais déclaré application/pdf (identify: false pour garder le
      # type déclaré du client, comme un blob non ré-identifié).
      user.classic_doc = {
        io: StringIO.new(png_bytes),
        filename: "fake.pdf",
        content_type: "application/pdf",
        identify: false
      }

      expect(user).not_to be_valid

      messages = user.errors[:classic_doc].join(" ")
      expect(messages).to include("ne correspond pas aux types autorisés")
      expect(messages).not_to include(I18n.t("upload_d_n_d.errors.mime_detection_failed"))
    end

    it "envoie au stockage un fichier identique à l'original (source rembobinée)" do
      user = ClassicDocUser.new
      # Hash + StringIO : c'est le MÊME IO que lit l'envoi au stockage au `save`.
      # Si la lecture MIME ne rembobinait pas, le blob stocké serait tronqué.
      user.classic_doc = { io: StringIO.new(pdf_bytes), filename: "doc.pdf", content_type: "application/pdf" }

      expect(user.save).to be(true)
      expect(user.reload.classic_doc.download).to eq(pdf_bytes)
    end
  end

  describe "has_many_attached + strict_mime_check" do
    before do
      stub_const(
        "ClassicDocsUser",
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          has_many_attached :classic_docs
          validates :classic_docs, file: { content_type: [ "application/pdf" ], strict_mime_check: true }
        end
      )
    end

    it "valide plusieurs PDF par leur contenu sans erreur de détection" do
      user = ClassicDocsUser.new
      user.classic_docs = [
        uploaded(pdf_bytes, filename: "a.pdf", type: "application/pdf"),
        uploaded(pdf_bytes, filename: "b.pdf", type: "application/pdf")
      ]

      expect(user).to be_valid
      expect(user.save).to be(true)
      expect(user.reload.classic_docs.count).to eq(2)
    end
  end
end
