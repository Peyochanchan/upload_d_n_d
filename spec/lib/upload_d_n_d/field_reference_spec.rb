# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::FieldReference do
  it 'resolves the constraints of the signed field' do
    token = described_class.generate(LimitedUser, :documents)

    expect(described_class.constraints(token, 'documents')).to eq(UploadDND::FieldConstraints.for(LimitedUser, :documents))
  end

  it 'rejects a tampered token' do
    token = described_class.generate(LimitedUser, :documents)

    expect { described_class.constraints("#{token}x", 'documents') }.to raise_error(described_class::Invalid)
    expect { described_class.constraints('garbage', 'documents') }.to raise_error(described_class::Invalid)
  end

  it 'rejects a token used for another attribute' do
    token = described_class.generate(LimitedUser, :documents)

    expect { described_class.constraints(token, 'avatar') }.to raise_error(described_class::Invalid)
  end

  it 'rejects a token signed for another purpose' do
    token = Rails.application.message_verifier('upload_d_n_d/field_reference').generate([ 'LimitedUser', 'documents' ])

    expect { described_class.constraints(token, 'documents') }.to raise_error(described_class::Invalid)
  end

  it 'rejects an unknown model or an attribute that is not an attachment' do
    verifier = Rails.application.message_verifier('upload_d_n_d/field_reference')
    unknown = verifier.generate([ 'NoSuchModel', 'documents' ], purpose: described_class::PURPOSE)
    not_attachment = verifier.generate([ 'LimitedUser', 'email' ], purpose: described_class::PURPOSE)

    expect { described_class.constraints(unknown, 'documents') }.to raise_error(described_class::Invalid)
    expect { described_class.constraints(not_attachment, 'email') }.to raise_error(described_class::Invalid)
  end
end
