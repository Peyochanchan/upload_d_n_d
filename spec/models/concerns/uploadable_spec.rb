# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::Uploadable do
  def create_blob(filename:, content_type:, data: "x" * 20)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data),
      filename: filename,
      content_type: content_type
    )
  end

  def create_temp_attachment(session_id:, attribute_name:, blob:)
    UploadDND::TemporaryAttachment.create!(
      session_id: session_id,
      attribute_name: attribute_name
    ).tap { |ta| ta.blob.attach(blob) }
  end

  describe "temp_upload_session_id" do
    it "stocke et lit la valeur via une ivar privée" do
      record = User.new

      record.temp_upload_session_id = "abc"
      expect(record.temp_upload_session_id).to eq("abc")
      expect(record.instance_variable_get(:@_temp_upload_session_id)).to eq("abc")
    end
  end

  describe "uploadable DSL" do
    before do
      stub_const(
        "UploadableDslUser",
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          include UploadDND::Uploadable

          has_one_attached :avatar
          has_many_attached :documents

          uploadable :avatar, content_type: [ "image/png" ], max_size: 1.megabyte
          uploadable :documents, content_type: [ "application/pdf" ], max_size: 1.megabyte, max_files: 2
        end
      )
    end

    it "expose les options via uploadable_attributes" do
      expect(UploadableDslUser.uploadable_attributes[:avatar][:content_type]).to eq([ "image/png" ])
      expect(UploadableDslUser.uploadable_attributes[:documents][:max_files]).to eq(2)
    end
  end

  describe "after_create :attach_temporary_uploads" do
    before do
      stub_const(
        "UploadableUser",
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          include UploadDND::Uploadable

          has_one_attached :avatar
          has_many_attached :documents

          uploadable :avatar, content_type: [ "image/png" ], max_size: 1.megabyte
          uploadable :documents, content_type: [ "application/pdf" ], max_size: 1.megabyte
        end
      )
    end

    it "ne fait rien sans temp_upload_session_id" do
      blob = create_blob(filename: "a.png", content_type: "image/png")
      create_temp_attachment(session_id: "sid", attribute_name: "avatar", blob: blob)

      record = UploadableUser.create!(name: "Test", email: "test@example.com")

      expect(record.avatar).not_to be_attached
      expect(UploadDND::TemporaryAttachment.where(session_id: "sid").count).to eq(1)
    end

    it "attache et supprime les fichiers temporaires (has_one + has_many)" do
      session_id = SecureRandom.uuid

      avatar_blob = create_blob(filename: "avatar.png", content_type: "image/png")
      doc1_blob = create_blob(filename: "doc1.pdf", content_type: "application/pdf")
      doc2_blob = create_blob(filename: "doc2.pdf", content_type: "application/pdf")

      create_temp_attachment(session_id: session_id, attribute_name: "avatar", blob: avatar_blob)
      create_temp_attachment(session_id: session_id, attribute_name: "documents", blob: doc1_blob)
      create_temp_attachment(session_id: session_id, attribute_name: "documents", blob: doc2_blob)

      record = UploadableUser.new(name: "Test", email: "test@example.com")
      record.temp_upload_session_id = session_id
      record.save!

      record.reload
      expect(record.avatar).to be_attached
      expect(record.documents.count).to eq(2)
      expect(UploadDND::TemporaryAttachment.where(session_id: session_id).count).to eq(0)
      expect(record.temp_upload_session_id).to be_nil
    end

    it "pour has_one_attached, n'écrase pas un avatar déjà attaché (et ne transfère que le premier)" do
      session_id = SecureRandom.uuid

      existing = create_blob(filename: "existing.png", content_type: "image/png")
      new1 = create_blob(filename: "new1.png", content_type: "image/png")
      new2 = create_blob(filename: "new2.png", content_type: "image/png")

      create_temp_attachment(session_id: session_id, attribute_name: "avatar", blob: new1)
      create_temp_attachment(session_id: session_id, attribute_name: "avatar", blob: new2)

      record = UploadableUser.new(name: "Test", email: "test@example.com")
      record.avatar.attach(existing)
      record.temp_upload_session_id = session_id
      record.save!

      record.reload
      expect(record.avatar.filename.to_s).to eq("existing.png")
      expect(UploadDND::TemporaryAttachment.where(session_id: session_id).count).to eq(0)
    end

    it "ignore les temporary_attachments dont l'attribut n'existe pas sur le record" do
      session_id = SecureRandom.uuid
      blob = create_blob(filename: "doc.pdf", content_type: "application/pdf")

      create_temp_attachment(session_id: session_id, attribute_name: "nonexistent_attribute", blob: blob)

      record = UploadableUser.new(name: "Test", email: "test@example.com")
      record.temp_upload_session_id = session_id
      record.save!

      expect(UploadDND::TemporaryAttachment.where(session_id: session_id).count).to eq(0)
    end
  end

  describe "FileValidator integration" do
    before do
      stub_const(
        "ValidatedUploadableUser",
        Class.new(ActiveRecord::Base) do
          self.table_name = "users"
          include UploadDND::Uploadable

          has_one_attached :avatar
          has_many_attached :documents

          uploadable :avatar, content_type: [ "image/png" ], max_size: 1 # 1 byte
          uploadable :documents, content_type: [ "application/pdf" ], max_size: 1.megabyte, max_files: 1
        end
      )
    end

    it "rejette un content_type non autorisé" do
      record = ValidatedUploadableUser.new(name: "Test", email: "test@example.com")
      record.avatar.attach(create_blob(filename: "a.jpg", content_type: "image/jpeg"))

      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to be_present
    end

    it "rejette un fichier trop gros" do
      record = ValidatedUploadableUser.new(name: "Test", email: "test@example.com")
      record.avatar.attach(create_blob(filename: "a.png", content_type: "image/png", data: "xx"))

      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to be_present
    end

    it "rejette le dépassement de max_files sur has_many_attached" do
      record = ValidatedUploadableUser.new(name: "Test", email: "test@example.com")
      record.documents.attach(create_blob(filename: "d1.pdf", content_type: "application/pdf"))
      record.documents.attach(create_blob(filename: "d2.pdf", content_type: "application/pdf"))

      expect(record).not_to be_valid
      expect(record.errors[:documents]).to be_present
    end
  end
end
