# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::CleanupTemporaryAttachmentsJob do
  describe "#perform" do
    it "destroys expired temporary attachments" do
      expired = create(:temporary_attachment, :expired)
      fresh = create(:temporary_attachment)

      described_class.perform_now

      expect(UploadDND::TemporaryAttachment.exists?(expired.id)).to be false
      expect(UploadDND::TemporaryAttachment.exists?(fresh.id)).to be true
    end

    it "respects a custom retention period" do
      UploadDND.configure { |c| c.temporary_files_retention = 1 }
      stale = create(:temporary_attachment)
      stale.update_column(:created_at, 2.days.ago)

      described_class.perform_now

      expect(UploadDND::TemporaryAttachment.exists?(stale.id)).to be false
    ensure
      UploadDND.reset_configuration!
    end
  end
end
