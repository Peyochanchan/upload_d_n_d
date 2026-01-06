require "rails_helper"

# Load the helper from templates
require_relative "../../../lib/generators/upload_d_n_d/templates/helpers/upload_helper"

RSpec.describe UploadDND::UploadHelper, type: :helper do
  # Include the helper module
  before do
    helper.class.include UploadDND::UploadHelper
  end

  describe "#upload_field" do
    let(:user) { User.create!(name: "Test User", email: "test@example.com") }

    before do
      allow(helper).to receive(:current_user_for_upload).and_return(user)
      allow(helper).to receive(:render)
    end

    it "renders the UploadComponent" do
      expect(helper).to receive(:render).with(
        an_instance_of(UploadDND::UploadComponent)
      )

      helper.upload_field(:avatar, record: user)
    end

    it "passes the attribute_name to the component" do
      component = nil
      allow(helper).to receive(:render) do |comp|
        component = comp
      end

      helper.upload_field(:documents, record: user)
      expect(component.attribute_name).to eq(:documents)
    end

    it "passes the record to the component" do
      component = nil
      allow(helper).to receive(:render) do |comp|
        component = comp
      end

      helper.upload_field(:avatar, record: user)
      expect(component.record).to eq(user)
    end

    it "passes options to the component" do
      component = nil
      allow(helper).to receive(:render) do |comp|
        component = comp
      end

      helper.upload_field(:avatar, record: user, multiple: true, max_size: 10.megabytes)
      expect(component.multiple).to be true
      expect(component.max_size).to eq(10.megabytes)
    end

    it "works without a record for temporary uploads" do
      component = nil
      allow(helper).to receive(:render) do |comp|
        component = comp
      end

      helper.upload_field(:avatar, accepted_types: '.jpg,.png')
      expect(component.record).to be_nil
      expect(component.accepted_types).to eq('.jpg,.png')
    end
  end

  describe "#current_user_for_upload" do
    context "when current_user is available" do
      let(:user) { User.create!(name: "Test User", email: "test@example.com") }

      it "returns the current_user" do
        # Define current_user method on the helper  with the user from let
        current_user_value = user
        helper.define_singleton_method(:current_user) { current_user_value }

        expect(helper.current_user_for_upload).to eq(user)
      end
    end

    context "when current_user is not available" do
      it "returns nil" do
        expect(helper.current_user_for_upload).to be_nil
      end
    end
  end

  describe "#file_icon_class" do
    it "returns pdf icon for .pdf files" do
      expect(helper.file_icon_class("document.pdf")).to eq("fa-file-pdf")
    end

    it "returns word icon for .doc files" do
      expect(helper.file_icon_class("document.doc")).to eq("fa-file-word")
    end

    it "returns word icon for .docx files" do
      expect(helper.file_icon_class("document.docx")).to eq("fa-file-word")
    end

    it "returns excel icon for .xls files" do
      expect(helper.file_icon_class("spreadsheet.xls")).to eq("fa-file-excel")
    end

    it "returns excel icon for .xlsx files" do
      expect(helper.file_icon_class("spreadsheet.xlsx")).to eq("fa-file-excel")
    end

    it "returns image icon for .jpg files" do
      expect(helper.file_icon_class("photo.jpg")).to eq("fa-file-image")
    end

    it "returns image icon for .jpeg files" do
      expect(helper.file_icon_class("photo.jpeg")).to eq("fa-file-image")
    end

    it "returns image icon for .png files" do
      expect(helper.file_icon_class("image.png")).to eq("fa-file-image")
    end

    it "returns image icon for .gif files" do
      expect(helper.file_icon_class("animation.gif")).to eq("fa-file-image")
    end

    it "returns image icon for .svg files" do
      expect(helper.file_icon_class("vector.svg")).to eq("fa-file-image")
    end

    it "returns archive icon for .zip files" do
      expect(helper.file_icon_class("archive.zip")).to eq("fa-file-archive")
    end

    it "returns archive icon for .rar files" do
      expect(helper.file_icon_class("archive.rar")).to eq("fa-file-archive")
    end

    it "returns archive icon for .7z files" do
      expect(helper.file_icon_class("archive.7z")).to eq("fa-file-archive")
    end

    it "returns video icon for .mp4 files" do
      expect(helper.file_icon_class("video.mp4")).to eq("fa-file-video")
    end

    it "returns video icon for .avi files" do
      expect(helper.file_icon_class("video.avi")).to eq("fa-file-video")
    end

    it "returns video icon for .mov files" do
      expect(helper.file_icon_class("video.mov")).to eq("fa-file-video")
    end

    it "returns generic file icon for unknown extensions" do
      expect(helper.file_icon_class("file.txt")).to eq("fa-file")
    end

    it "is case insensitive" do
      expect(helper.file_icon_class("DOCUMENT.PDF")).to eq("fa-file-pdf")
      expect(helper.file_icon_class("Photo.JPG")).to eq("fa-file-image")
    end
  end

  describe "#file_type_badge_class" do
    it "returns success badge for image types" do
      expect(helper.file_type_badge_class("image/jpeg")).to eq("badge-success")
      expect(helper.file_type_badge_class("image/png")).to eq("badge-success")
      expect(helper.file_type_badge_class("image/gif")).to eq("badge-success")
    end

    it "returns danger badge for PDF" do
      expect(helper.file_type_badge_class("application/pdf")).to eq("badge-danger")
    end

    it "returns primary badge for Word documents" do
      expect(helper.file_type_badge_class("application/msword")).to eq("badge-primary")
      expect(helper.file_type_badge_class("application/vnd.openxmlformats-officedocument.wordprocessingml.document")).to eq("badge-primary")
    end

    it "returns success badge for Excel documents" do
      expect(helper.file_type_badge_class("application/vnd.ms-excel")).to eq("badge-success")
      expect(helper.file_type_badge_class("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")).to eq("badge-success")
    end

    it "returns secondary badge for unknown types" do
      expect(helper.file_type_badge_class("text/plain")).to eq("badge-secondary")
      expect(helper.file_type_badge_class("application/json")).to eq("badge-secondary")
    end
  end

  describe "#uploaded_files_list" do
    let(:user) { User.create!(name: "Test User", email: "test@example.com") }

    before do
      allow(helper).to receive(:render)
    end

    context "when record has no files attached" do
      it "returns nil" do
        expect(helper.uploaded_files_list(:avatar, record: user)).to be_nil
      end
    end

    context "when record has a file attached (has_one)" do
      before do
        user.avatar.attach(
          io: StringIO.new("fake avatar"),
          filename: "avatar.jpg",
          content_type: "image/jpeg"
        )
      end

      it "renders the files_list partial" do
        expect(helper).to receive(:render).with(
          partial: 'upload_d_n_d/shared/files_list',
          locals: hash_including(attribute_name: :avatar)
        )

        helper.uploaded_files_list(:avatar, record: user)
      end
    end

    context "when attribute does not exist on record" do
      it "returns nil" do
        expect(helper.uploaded_files_list(:nonexistent, record: user)).to be_nil
      end
    end

    context "when record is nil" do
      it "returns nil" do
        expect(helper.uploaded_files_list(:avatar, record: nil)).to be_nil
      end
    end
  end
end
