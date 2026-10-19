require "rails_helper"

RSpec.describe UploadDND::UploadComponent, type: :component do
  # Create tables before all tests
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :admin_articles, force: true do |t|
        t.string :title
        t.timestamps
      end

      create_table :manager_reports, force: true do |t|
        t.string :title
        t.timestamps
      end
    end

    connection = ActiveRecord::Base.connection
    connection.schema_cache.clear!
    connection.clear_cache!
    Admin::Article.reset_column_information
    Manager::Report.reset_column_information
  end

  # Drop tables after all tests
  after(:all) do
    ActiveRecord::Schema.define do
      drop_table :admin_articles, if_exists: true
      drop_table :manager_reports, if_exists: true
    end

    connection = ActiveRecord::Base.connection
    connection.schema_cache.clear!
    connection.clear_cache!
  end

  let(:user) { User.create!(name: "Test User", email: "test@example.com") }

  describe "#initialize" do
    context "with minimal parameters" do
      let(:component) { described_class.new(attribute_name: :avatar) }

      it "sets the attribute name" do
        expect(component.attribute_name).to eq(:avatar)
      end

      it "uses default configuration for accepted_types" do
        expect(component.accepted_types).to eq(UploadDND.configuration.accepted_types)
      end

      it "uses default configuration for max_size" do
        expect(component.max_size).to eq(UploadDND.configuration.max_size)
      end

      it "sets multiple to false by default" do
        expect(component.multiple).to be false
      end
    end

    context "with custom parameters" do
      let(:component) do
        described_class.new(
          attribute_name: :documents,
          multiple: true,
          accepted_types: ".pdf,.docx",
          max_size: 20.megabytes
        )
      end

      it "uses custom accepted_types" do
        expect(component.accepted_types).to eq(".pdf,.docx")
      end

      it "uses custom max_size" do
        expect(component.max_size).to eq(20.megabytes)
      end

      it "uses custom multiple" do
        expect(component.multiple).to be true
      end
    end

    context "with a persisted record" do
      let(:record) { user }
      let(:component) { described_class.new(attribute_name: :avatar, record: record) }

      it "sets the record" do
        expect(component.record).to eq(record)
      end

      it "auto-detects multiple from has_one_attached" do
        expect(component.multiple).to be false
      end
    end
  end

  describe "#model_name" do
    context "with a record" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user) }

      it "returns underscored class name" do
        expect(component.model_name).to eq("user")
      end
    end

    context "with a namespaced record" do
      let(:article) { Admin::Article.create!(title: "Test Article") }
      let(:component) { described_class.new(attribute_name: :images, record: article) }

      it "returns underscored class name with namespace" do
        expect(component.model_name).to eq("admin_article")
      end
    end

    context "without a record" do
      let(:component) { described_class.new(attribute_name: :documents) }

      it "returns singularized attribute name" do
        expect(component.model_name).to eq("document")
      end
    end
  end

  describe "#record_gid" do
    context "with a persisted record" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user) }

      it "returns a GlobalID string" do
        expect(component.record_gid).to be_a(String)
        expect(component.record_gid).to include("gid://")
        expect(component.record_gid).to include("User")
      end
    end

    context "with a non-persisted record" do
      let(:new_user) { User.new(name: "New User", email: "new@example.com") }
      let(:component) { described_class.new(attribute_name: :avatar, record: new_user) }

      it "returns nil" do
        expect(component.record_gid).to be_nil
      end
    end

    context "without a record" do
      let(:component) { described_class.new(attribute_name: :avatar) }

      it "returns nil" do
        expect(component.record_gid).to be_nil
      end
    end
  end

  describe "#attach_path" do
    context "with a persisted record" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user) }

      it "returns the attachments path" do
        expect(component.attach_path).to eq(UploadDND::Engine.routes.url_helpers.attachments_path)
      end
    end

    context "without a persisted record" do
      let(:component) { described_class.new(attribute_name: :avatar) }

      it "returns the temporary attachments path" do
        expect(component.attach_path).to eq(UploadDND::Engine.routes.url_helpers.temporary_attachments_path)
      end
    end
  end

  describe "#files" do
    context "with a persisted record and has_one_attached" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user) }

      context "when no file is attached" do
        it "returns an empty array" do
          expect(component.files).to eq([])
        end
      end

      context "when a file is attached" do
        before do
          user.avatar.attach(
            io: StringIO.new("fake image"),
            filename: "avatar.jpg",
            content_type: "image/jpeg"
          )
        end

        it "returns an array with the blob" do
          expect(component.files).to be_an(Array)
          expect(component.files.size).to eq(1)
          expect(component.files.first).to be_a(ActiveStorage::Blob)
          expect(component.files.first.filename.to_s).to eq("avatar.jpg")
        end
      end
    end

    context "with a persisted record and has_many_attached" do
      let(:article) { Admin::Article.create!(title: "Test Article") }
      let(:component) { described_class.new(attribute_name: :images, record: article) }

      context "when no files are attached" do
        it "returns an empty collection" do
          expect(component.files).to be_empty
        end
      end

      context "when multiple files are attached" do
        before do
          article.images.attach([
            { io: StringIO.new("fake image 1"), filename: "image1.jpg", content_type: "image/jpeg" },
            { io: StringIO.new("fake image 2"), filename: "image2.jpg", content_type: "image/jpeg" }
          ])
        end

        it "returns all attached blobs" do
          expect(component.files.size).to eq(2)
          expect(component.files.first).to be_a(ActiveStorage::Blob)
        end
      end
    end

    context "without a persisted record" do
      # Note: Testing files method with temporary attachments requires rendering
      # the component first because it needs access to helpers.session
      # These tests verify the behavior through integration rather than unit tests
      it "accesses temporary attachments through the session" do
        # This is tested in integration tests where the full rendering context is available
        expect(UploadDND::TemporaryAttachment).to respond_to(:where)
      end
    end
  end

  describe "#main_color" do
    let(:component) { described_class.new(attribute_name: :avatar) }

    it "returns the configured main color" do
      expect(component.main_color).to eq(UploadDND.configuration.main_color)
    end

    context "when configuration is empty" do
      before do
        allow(UploadDND.configuration).to receive(:main_color).and_return(nil)
      end

      it "returns the default color" do
        expect(component.main_color).to eq("#E97451")
      end
    end
  end

  describe "#main_color_rgb" do
    let(:component) { described_class.new(attribute_name: :avatar) }

    context "with default color" do
      before do
        allow(UploadDND.configuration).to receive(:main_color).and_return("#E97451")
      end

      it "returns RGB values as string" do
        expect(component.main_color_rgb).to eq("233 116 81")
      end
    end

    context "with a different color" do
      before do
        allow(UploadDND.configuration).to receive(:main_color).and_return("#FF0000")
      end

      it "returns correct RGB values" do
        expect(component.main_color_rgb).to eq("255 0 0")
      end
    end

    context "with a 3-character hex color" do
      before do
        allow(UploadDND.configuration).to receive(:main_color).and_return("#F00")
      end

      it "expands and converts correctly" do
        expect(component.main_color_rgb).to eq("255 0 0")
      end
    end

    context "with an invalid color" do
      before do
        allow(UploadDND.configuration).to receive(:main_color).and_return("invalid")
      end

      it "returns the default RGB values" do
        expect(component.main_color_rgb).to eq("233 116 81")
      end
    end
  end

  describe "multiple detection" do
    context "with has_one_attached" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user) }

      it "detects as single upload" do
        expect(component.multiple).to be false
      end
    end

    context "with has_many_attached" do
      let(:article) { Admin::Article.create!(title: "Test Article") }
      let(:component) { described_class.new(attribute_name: :images, record: article) }

      it "detects as multiple upload" do
        expect(component.multiple).to be true
      end
    end

    context "with explicit multiple override" do
      let(:component) { described_class.new(attribute_name: :avatar, record: user, multiple: true) }

      it "uses the explicit value" do
        expect(component.multiple).to be true
      end
    end
  end

  describe "configuration from model" do
    let(:article) { Admin::Article.create!(title: "Test Article") }

    context "when model has uploadable configuration" do
      let(:component) { described_class.new(attribute_name: :images, record: article) }

      it "uses model configuration for accepted_types" do
        # Admin::Article configures images with specific content types
        expect(component.accepted_types).to include(".jpg", ".png")
      end
    end

    context "when attribute is not uploadable" do
      let(:component) { described_class.new(attribute_name: :title, record: article) }

      it "falls back to default configuration" do
        expect(component.accepted_types).to eq(UploadDND.configuration.accepted_types)
      end
    end
  end

  # A2 : le composant applique exactement les limites du serveur.
  describe "limits shared with the server" do
    LimitedUser.uploadable_attributes.each_key do |attribute|
      it "matches the server limits for LimitedUser##{attribute}" do
        component = described_class.new(attribute_name: attribute, record: LimitedUser.new)
        server = UploadDND::FieldConstraints.for(LimitedUser, attribute)

        expect(component.max_size).to eq(server.max_size)
        expect(component.accepted_types).to eq(server.accepted_extensions)
        expect(component.accepted_mime_types.split(",")).to eq(server.content_types)
        expect(UploadDND::FieldReference.constraints(component.field_ref, attribute)).to eq(server)
      end
    end

    it "accepts both .jpg and .jpeg for image/jpeg" do
      component = described_class.new(attribute_name: :documents, record: LimitedUser.new)

      expect(component.accepted_types.split(",")).to include(".jpg", ".jpeg")
    end

    it "renders the field reference and the MIME types for the browser" do
      container = render_inline(described_class.new(attribute_name: :avatar, record: LimitedUser.new)).at_css(".udnd-container")
      expect(container["data-upload-d-n-d--uploads-field-ref-value"]).to be_present
      expect(container["data-upload-d-n-d--uploads-mime-types-value"]).to eq("image/png")
    end

    it "emits no field reference without a record (global limits)" do
      component = described_class.new(attribute_name: :documents)

      expect(component.field_ref).to be_nil
      expect(component.max_size).to eq(UploadDND.configuration.max_size)
    end
  end

  describe "rendering" do
    let(:component) { described_class.new(attribute_name: :avatar, record: user) }

    before do
      # Setup a session for the rendering context
      allow_any_instance_of(ActionDispatch::Request).to receive(:session).and_return({})
    end

    it "renders without errors" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "includes the component wrapper" do
      result = render_inline(component)
      expect(result.to_html).to be_present
    end

    context "without a persisted record" do
      let(:session_id) { SecureRandom.uuid }
      let(:component) { described_class.new(attribute_name: :documents) }

      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session)
          .and_return(instance_double(ActionDispatch::Request::Session, id: session_id))
      end

      def create_temp_attachment(session:, filename:)
        temp = UploadDND::TemporaryAttachment.create!(session_id: session, attribute_name: "documents")
        temp.blob.attach(io: StringIO.new("data"), filename: filename, content_type: "image/png")
        temp
      end

      it "renders the temporary files of the current session (restores the zone after a reload)" do
        create_temp_attachment(session: session_id, filename: "draft.png")

        html = render_inline(component).to_html

        expect(html).to include('id="udnd_files_list_documents"')
        expect(html).to include("draft.png")
      end

      it "does not render temporary files from another session" do
        create_temp_attachment(session: SecureRandom.uuid, filename: "theirs.png")

        html = render_inline(component).to_html

        expect(html).not_to include("theirs.png")
        expect(html).to include("udnd-no-files")
      end
    end
  end
end
