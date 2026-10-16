# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::AttachmentLookup do
  let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

  describe '.find' do
    it 'returns the has_one_attached proxy' do
      expect(described_class.find(user, 'avatar')).to be_a(ActiveStorage::Attached::One)
    end

    it 'returns the has_many_attached proxy' do
      expect(described_class.find(user, :documents)).to be_a(ActiveStorage::Attached::Many)
    end

    it 'returns nil for an unknown attribute' do
      expect(described_class.find(user, 'nonexistent')).to be_nil
    end

    it 'returns nil for a column that is not an attachment' do
      expect(described_class.find(user, 'email')).to be_nil
    end

    it 'never calls a method that is not an attachment' do
      expect(user).not_to receive(:destroy)

      expect(described_class.find(user, 'destroy')).to be_nil
      expect(User.exists?(user.id)).to be true
    end

    it 'returns nil for a blank attribute name or a nil record' do
      expect(described_class.find(user, '')).to be_nil
      expect(described_class.find(nil, 'avatar')).to be_nil
    end

    it 'returns nil for an object without ActiveStorage reflection' do
      expect(described_class.find(Object.new, 'avatar')).to be_nil
    end
  end
end
