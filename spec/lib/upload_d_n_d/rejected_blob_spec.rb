# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::RejectedBlob do
  include ActiveJob::TestHelper

  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png')
  end

  after { UploadDND.reset_configuration! }

  describe '.discard' do
    it 'purges a recent blob without attachment' do
      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'keeps a blob attached to a record' do
      user = User.create!(name: 'Test', email: 'test@example.com')
      user.avatar.attach(blob)

      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      expect(user.reload.avatar).to be_attached
    end

    it 'keeps a blob held by a TemporaryAttachment' do
      temp = UploadDND::TemporaryAttachment.create!(session_id: 'sid', attribute_name: 'avatar')
      temp.blob.attach(blob)

      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      expect(temp.reload.blob).to be_attached
    end

    it 'keeps a blob older than the purge window' do
      blob.update_column(:created_at, 2.hours.ago)

      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it 'honours a custom purge window' do
      UploadDND.configuration.rejected_blob_purge_window = 3.hours
      blob.update_column(:created_at, 2.hours.ago)

      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'purges nothing when the purge window is disabled (nil)' do
      UploadDND.configuration.rejected_blob_purge_window = nil

      perform_enqueued_jobs { described_class.discard(blob) }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it 'ignores nil' do
      expect { described_class.discard(nil) }.not_to have_enqueued_job
    end

    it 'enqueues UploadDND::PurgeRejectedBlobJob, not ActiveStorage::PurgeJob' do
      expect { described_class.discard(blob) }
        .to have_enqueued_job(UploadDND::PurgeRejectedBlobJob).with(blob.id)
    end
  end
end
