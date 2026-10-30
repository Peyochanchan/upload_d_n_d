# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::SignedTarget do
  let(:user) { User.create!(name: 'T', email: 't-signed-target@example.com') }

  describe '.generate / .verify' do
    it 'round-trips model, attribute, record_id and namespace' do
      token = described_class.generate(User, :avatar, record_id: user.id, namespace: [ :admin ])
      target = described_class.verify(token)

      expect(target.model_class).to eq(User)
      expect(target.attribute).to eq('avatar')
      expect(target.record_id).to eq(user.id)
      expect(target.namespace).to eq([ :admin ])
    end

    it 'carries no record_id for a temporary target' do
      target = described_class.verify(described_class.generate(User, :documents))

      expect(target.record_id).to be_nil
      expect(target.namespace).to be_nil
    end

    it 'rejects a forged / unsigned token' do
      expect { described_class.verify('forged.token.value') }.to raise_error(described_class::Invalid)
    end

    it 'rejects a blank token' do
      expect { described_class.verify(nil) }.to raise_error(described_class::Invalid)
      expect { described_class.verify('') }.to raise_error(described_class::Invalid)
    end

    it 'rejects an attribute not declared uploadable (F3)' do
      # internal_file est un has_one_attached NON déclaré uploadable.
      token = described_class.generate(User, :internal_file)

      expect { described_class.verify(token) }.to raise_error(described_class::Invalid)
    end

    it 'rejects an unknown model' do
      token = described_class.generate(User, :avatar)
      # On force une charge signée vers un modèle inexistant via le même verifier.
      forged = Rails.application.message_verifier('upload_d_n_d/signed_target')
                    .generate([ 'Nope::Ghost', 'avatar', nil, nil ], purpose: described_class::PURPOSE)

      expect { described_class.verify(forged) }.to raise_error(described_class::Invalid)
      expect(described_class.verify(token)).to be_a(described_class::Target) # sanity
    end
  end

  describe 'Target#record' do
    it 'resolves the signed record' do
      target = described_class.verify(described_class.generate(User, :avatar, record_id: user.id))

      expect(target.record).to eq(user)
    end

    it 'returns nil for a temporary target (no record_id)' do
      target = described_class.verify(described_class.generate(User, :avatar))

      expect(target.record).to be_nil
    end

    it 'raises RecordNotFound when the signed record no longer exists' do
      target = described_class.verify(described_class.generate(User, :avatar, record_id: 999_999))

      expect { target.record }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'Target#constraints' do
    it 'derives the field constraints from the model' do
      target = described_class.verify(described_class.generate(LimitedUser, :avatar))

      expect(target.constraints).to eq(UploadDND::FieldConstraints.for(LimitedUser, :avatar))
    end
  end
end
