# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::ApplicationHelper, type: :helper do
  describe "#udnd_remove_file_url" do
    let(:record) { User.create!(name: "Test", email: "test-helper@example.com") }
    let(:attachment) { double("Attachment", id: 42) }

    after { UploadDND.reset_configuration! }

    context "en mode :engine (défaut)" do
      it "builds the engine route with record_gid, without any host route" do
        url = helper.udnd_remove_file_url(record, attachment, "documents")

        expect(url).to include("/attachments/42")
        expect(url).to include("attribute_name=documents")
        expect(url).to include("record_gid=")
      end
    end

    context "en mode :host (legacy)" do
      before { UploadDND.configure { |c| c.delete_route = :host } }

      it "builds the URL on the record's remove_file member route" do
        routes = double(polymorphic_path: "/users/#{record.id}")
        allow(helper).to receive(:main_app).and_return(routes)

        url = helper.udnd_remove_file_url(record, attachment, "documents")

        expect(url).to eq("/users/#{record.id}/remove_file?attribute_name=documents&file_id=42")
      end

      it "raises UnroutableRecordError with resolve() guidance when the record has no polymorphic route" do
        routes = double
        allow(routes).to receive(:polymorphic_path)
          .and_raise(NoMethodError, "undefined method 'convention_path'")
        allow(helper).to receive(:main_app).and_return(routes)

        expect {
          helper.udnd_remove_file_url(record, attachment, "file")
        }.to raise_error(UploadDND::UnroutableRecordError, /resolve\("User"\)|resolve\(/) do |error|
          expect(error.message).to include("User")
          expect(error.message).to include("resolve(")
          expect(error.message).to include("udnd_remove_file_url")
        end
      end
    end
  end
end
