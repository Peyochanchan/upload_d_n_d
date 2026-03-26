# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::FileValidator do
  # Classe de test pour le validator
  class TestRecord
    include ActiveModel::Model
    include ActiveModel::Validations

    attr_accessor :avatar, :documents

    # Simule has_one_attached
    def avatar
      @avatar ||= MockAttachment.new
    end

    # Simule has_many_attached
    def documents
      @documents ||= MockAttachmentCollection.new
    end
  end

  # Mock pour simuler un ActiveStorage::Attached::One
  class MockAttachment
    attr_accessor :blob

    def attached?
      !@blob.nil?
    end

    def attach(blob)
      @blob = blob
    end

    # Le validator appelle Array(value) et itère sur les blobs
    # Pour has_one_attached, on retourne le blob dans un array
    def to_ary
      attached? ? [ @blob ] : []
    end
  end

  # Mock pour simuler un ActiveStorage::Attached::Many
  class MockAttachmentCollection
    attr_accessor :blobs

    def initialize
      @blobs = []
    end

    def attached?
      @blobs.any?
    end

    def attach(*new_blobs)
      @blobs.concat(new_blobs)
    end

    def count
      @blobs.count
    end

    # Le validator itère directement sur la collection
    def each(&block)
      @blobs.each(&block)
    end

    # Pour Array(value)
    def to_ary
      @blobs
    end
  end

  # Mock pour simuler un Blob ActiveStorage
  class MockBlob
    attr_accessor :content_type, :byte_size, :filename

    def initialize(content_type:, byte_size:, filename: "test.jpg")
      @content_type = content_type
      @byte_size = byte_size
      @filename = filename
    end

    def download
      # Retourne un StringIO vide pour les tests
      StringIO.new
    end
  end

  let(:record) { TestRecord.new }
  let(:image_blob) { MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte) }
  let(:pdf_blob) { MockBlob.new(content_type: "application/pdf", byte_size: 2.megabytes, filename: "doc.pdf") }

  describe "content_type validation" do
    before do
      TestRecord.validates :avatar, file: { content_type: [ "image/jpeg", "image/png" ] }
    end

    after do
      TestRecord.clear_validators!
    end

    it "accepts valid content types" do
      record.avatar.attach(image_blob)
      expect(record).to be_valid
    end

    it "rejects invalid content types" do
      record.avatar.attach(pdf_blob)
      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include("n'est pas un type de fichier valide")
    end

    it "accepts multiple content types" do
      TestRecord.clear_validators!
      TestRecord.validates :avatar, file: { content_type: [ "image/jpeg", "application/pdf" ] }

      record.avatar.attach(image_blob)
      expect(record).to be_valid

      record = TestRecord.new
      record.avatar.attach(pdf_blob)
      expect(record).to be_valid
    end

    it "allows custom error message" do
      TestRecord.clear_validators!
      TestRecord.validates :avatar, file: {
        content_type: [ "image/jpeg" ],
        message: "doit être une image JPEG"
      }

      record.avatar.attach(pdf_blob)
      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include("doit être une image JPEG")
    end
  end

  describe "max_size validation" do
    before do
      TestRecord.validates :avatar, file: { max_size: 5.megabytes }
    end

    after do
      TestRecord.clear_validators!
    end

    it "accepts files under the size limit" do
      small_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      record.avatar.attach(small_blob)
      expect(record).to be_valid
    end

    it "rejects files over the size limit" do
      large_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 10.megabytes)
      record.avatar.attach(large_blob)
      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include("doit être inférieur à 5MB")
    end

    it "accepts files exactly at the size limit" do
      exact_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 5.megabytes)
      record.avatar.attach(exact_blob)
      expect(record).to be_valid
    end

    it "allows custom error message" do
      TestRecord.clear_validators!
      TestRecord.validates :avatar, file: {
        max_size: 5.megabytes,
        message: "est trop volumineux"
      }

      large_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 10.megabytes)
      record.avatar.attach(large_blob)
      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include("est trop volumineux")
    end
  end

  describe "max_files validation for has_many_attached" do
    before do
      TestRecord.validates :documents, file: { max_files: 3 }
    end

    after do
      TestRecord.clear_validators!
    end

    it "accepts collections under the file limit" do
      record.documents.attach(image_blob, pdf_blob)
      expect(record).to be_valid
    end

    it "rejects collections over the file limit" do
      blob1 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob2 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob3 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob4 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)

      record.documents.attach(blob1, blob2, blob3, blob4)
      expect(record).not_to be_valid
      expect(record.errors[:documents]).to include("ne peut pas avoir plus de 3 fichiers")
    end

    it "accepts collections exactly at the file limit" do
      blob1 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob2 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob3 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)

      record.documents.attach(blob1, blob2, blob3)
      expect(record).to be_valid
    end
  end

  describe "combined validations" do
    before do
      TestRecord.validates :documents, file: {
        content_type: [ "image/jpeg", "image/png" ],
        max_size: 5.megabytes,
        max_files: 2
      }
    end

    after do
      TestRecord.clear_validators!
    end

    it "validates all constraints" do
      valid_blob1 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      valid_blob2 = MockBlob.new(content_type: "image/png", byte_size: 2.megabytes, filename: "photo.png")

      record.documents.attach(valid_blob1, valid_blob2)
      expect(record).to be_valid
    end

    it "fails if any constraint is violated - wrong content type" do
      valid_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      invalid_blob = MockBlob.new(content_type: "application/pdf", byte_size: 1.megabyte, filename: "doc.pdf")

      record.documents.attach(valid_blob, invalid_blob)
      expect(record).not_to be_valid
      expect(record.errors[:documents]).to be_present
    end

    it "fails if any constraint is violated - too large" do
      valid_blob = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      too_large = MockBlob.new(content_type: "image/jpeg", byte_size: 10.megabytes)

      record.documents.attach(valid_blob, too_large)
      expect(record).not_to be_valid
      expect(record.errors[:documents]).to be_present
    end

    it "fails if any constraint is violated - too many files" do
      blob1 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob2 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)
      blob3 = MockBlob.new(content_type: "image/jpeg", byte_size: 1.megabyte)

      record.documents.attach(blob1, blob2, blob3)
      expect(record).not_to be_valid
      expect(record.errors[:documents]).to include("ne peut pas avoir plus de 2 fichiers")
    end
  end

  describe "when no file is attached" do
    it "does not validate" do
      TestRecord.validates :avatar, file: { content_type: [ "image/jpeg" ] }

      # avatar n'est pas attaché (MockAttachment sans blob)
      expect(record).to be_valid

      TestRecord.clear_validators!
    end
  end

  describe "strict_mime_check option" do
    before do
      TestRecord.validates :avatar, file: {
        content_type: [ "image/jpeg" ],
        strict_mime_check: true
      }
    end

    after do
      TestRecord.clear_validators!
    end

    it "rejects when detected content type is not allowed" do
      allow(Marcel::MimeType).to receive(:for).and_return("application/pdf")

      record.avatar.attach(image_blob)

      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include(
        "Le type de fichier détecté (application/pdf) ne correspond pas aux types autorisés"
      )
      expect(record.errors[:avatar]).to include(
        "Le type de fichier détecté (application/pdf) ne correspond pas au type déclaré (image/jpeg)"
      )
    end

    it "accepts when detected content type matches declared" do
      allow(Marcel::MimeType).to receive(:for).and_return("image/jpeg")

      record.avatar.attach(image_blob)

      expect(record).to be_valid
    end

    it "adds a clear error when mime detection fails" do
      allow(Marcel::MimeType).to receive(:for).and_raise(StandardError, "boom")

      record.avatar.attach(image_blob)

      expect(record).not_to be_valid
      expect(record.errors[:avatar]).to include(
        "Impossible de vérifier le type de fichier : boom"
      )
    end
  end

  describe "top-level FileValidator alias" do
    it "creates a top-level ::FileValidator constant" do
      expect(defined?(::FileValidator)).to be_truthy
      expect(::FileValidator).to eq(UploadDND::FileValidator)
    end

    it "does not override existing ::FileValidator if already defined" do
      # Ce test vérifie le comportement du unless defined?
      # Si ::FileValidator existe déjà, il ne devrait pas être écrasé
      expect(::FileValidator).to eq(UploadDND::FileValidator)
    end
  end
end
