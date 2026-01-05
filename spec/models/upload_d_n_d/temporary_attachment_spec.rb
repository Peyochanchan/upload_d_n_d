# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::TemporaryAttachment, type: :model do
  # S'assurer que la table existe pour tous les tests
  before(:all) do
    unless ActiveRecord::Base.connection.table_exists?(:upload_d_n_d_temporary_attachments)
      ActiveRecord::Schema.define do
        create_table :upload_d_n_d_temporary_attachments do |t|
          t.string :session_id, null: false
          t.string :attribute_name, null: false
          t.integer :user_id
          t.timestamps
        end

        add_index :upload_d_n_d_temporary_attachments, :session_id
        add_index :upload_d_n_d_temporary_attachments, :user_id
      end
    end
  end

  describe 'validations' do
    it { should validate_presence_of(:session_id) }
    it { should validate_presence_of(:attribute_name) }
  end

  describe 'associations' do
    it 'has one attached blob' do
      temp_attachment = create(:temporary_attachment)
      expect(temp_attachment.blob).to be_attached
    end
  end

  describe 'scopes' do
    let(:session_id) { SecureRandom.uuid }
    let!(:temp1) { create(:temporary_attachment, session_id: session_id) }
    let!(:temp2) { create(:temporary_attachment, session_id: SecureRandom.uuid) }

    describe '.for_session' do
      it 'returns attachments for the given session' do
        expect(described_class.for_session(session_id)).to include(temp1)
        expect(described_class.for_session(session_id)).not_to include(temp2)
      end
    end

    describe '.for_attribute' do
      let!(:temp3) { create(:temporary_attachment, attribute_name: 'documents') }

      it 'returns attachments for the given attribute name' do
        results = described_class.for_attribute('documents')
        expect(results).to include(temp3)
        expect(results).not_to include(temp1)
      end
    end

    describe '.for_user' do
      let!(:temp4) { create(:temporary_attachment, :with_user) }

      it 'returns attachments for the given user' do
        expect(described_class.for_user(1)).to include(temp4)
        expect(described_class.for_user(1)).not_to include(temp1)
      end
    end

    describe '.expired' do
      let!(:expired_temp) { create(:temporary_attachment, :expired) }
      let!(:recent_temp) { create(:temporary_attachment) }

      it 'returns expired attachments' do
        expect(described_class.expired).to include(expired_temp)
        expect(described_class.expired).not_to include(recent_temp)
      end
    end
  end

  describe '.cleanup_expired!' do
    let!(:expired1) { create(:temporary_attachment, :expired) }
    let!(:expired2) { create(:temporary_attachment, :expired) }
    let!(:recent) { create(:temporary_attachment) }

    it 'destroys expired attachments' do
      expect {
        described_class.cleanup_expired!
      }.to change(described_class, :count).by(-2)

      expect(described_class.exists?(expired1.id)).to be_falsey
      expect(described_class.exists?(expired2.id)).to be_falsey
      expect(described_class.exists?(recent.id)).to be_truthy
    end

    it 'purges associated blobs' do
      blob_id = expired1.blob.blob.id
      described_class.cleanup_expired!

      expect(ActiveStorage::Blob.exists?(blob_id)).to be_falsey
    end
  end

  describe 'instance methods' do
    let(:temp_attachment) { create(:temporary_attachment) }

    describe '#filename' do
      it 'returns the blob filename' do
        expect(temp_attachment.filename).to eq('test.png')
      end
    end

    describe '#content_type' do
      it 'returns the blob content type' do
        expect(temp_attachment.content_type).to eq('image/png')
      end
    end

    describe '#byte_size' do
      it 'returns the blob byte size' do
        expect(temp_attachment.byte_size).to be > 0
      end
    end

    describe '#url' do
      it 'returns a URL to the blob' do
        expect(temp_attachment.url).to be_present
        expect(temp_attachment.url).to include('/rails/active_storage/blobs')
      end
    end
  end

  describe 'callbacks' do
    describe 'before_destroy' do
      it 'purges the blob when destroyed' do
        temp_attachment = create(:temporary_attachment)
        blob_id = temp_attachment.blob.blob.id

        temp_attachment.destroy

        expect(ActiveStorage::Blob.exists?(blob_id)).to be_falsey
      end
    end
  end
end
