# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::FieldConstraints do
  after { UploadDND.reset_configuration! }

  def blob(data: "x" * 5, content_type: 'image/png', filename: 'x.png')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type, identify: false)
  end

  describe '.for' do
    it 'reads the uploadable limits of the field' do
      constraints = described_class.for(LimitedUser, :documents)

      expect(constraints.max_size).to eq(2.kilobytes)
      expect(constraints.content_types).to eq([ 'application/pdf', 'image/jpeg' ])
      expect(constraints.strict_mime_check).to be false
    end

    it 'falls back on the global configuration for each limit the model leaves out' do
      UploadDND.configuration.accepted_types = '.pdf'
      UploadDND.configuration.strict_mime_check = true

      constraints = described_class.for(LimitedUser, :cover)

      expect(constraints.max_size).to eq(20)
      expect(constraints.content_types).to eq([ 'application/pdf' ])
      expect(constraints.strict_mime_check).to be true
    end

    it 'keeps an explicit strict_mime_check: false over the global setting' do
      UploadDND.configuration.strict_mime_check = true

      expect(described_class.for(LimitedUser, :avatar).strict_mime_check).to be false
    end

    it 'uses the global configuration for a field without uploadable' do
      expect(described_class.for(User, :avatar)).to eq(described_class.global)
      expect(described_class.for(LimitedUser, :unknown)).to eq(described_class.global)
    end
  end

  it 'is a value object: equal by values, immutable' do
    a = described_class.new(max_size: 10, content_types: [ 'image/png' ], strict_mime_check: false)
    b = described_class.new(max_size: 10, content_types: [ 'image/png' ], strict_mime_check: false)

    expect(a).to eq(b)
    expect(a).to be_frozen
    expect(a.content_types).to be_frozen
  end

  it 'lists every extension of the accepted types' do
    expect(described_class.for(LimitedUser, :documents).accepted_extensions).to eq('.pdf,.jpg,.jpeg')
  end

  describe '#violation' do
    let(:constraints) { described_class.for(LimitedUser, :avatar) }

    it 'accepts a blob within the limits' do
      expect(constraints.violation(blob)).to be_nil
    end

    it 'detects a blob too large' do
      expect(constraints.violation(blob(data: "x" * 11))).to eq(:too_large)
    end

    it 'detects a type not accepted' do
      expect(constraints.violation(blob(content_type: 'application/pdf', filename: 'x.pdf'))).to eq(:invalid_type)
    end

    context 'with strict_mime_check' do
      let(:constraints) { described_class.new(max_size: 1.megabyte, content_types: [ 'image/png', 'application/pdf' ], strict_mime_check: true) }

      it 'detects a declared type that differs from the content' do
        expect(constraints.violation(blob(data: "%PDF-1.4\n%fake\n"))).to eq(:suspicious_type)
      end

      it 'reports a detection failure without leaking the exception' do
        allow(Marcel::MimeType).to receive(:for).and_raise(StandardError, 'boom')

        violation = constraints.violation(blob)

        expect(violation).to eq(:mime_detection_failed)
        expect(constraints.error_message(violation)).not_to include('boom')
      end
    end
  end

  describe '#error_message' do
    let(:constraints) { described_class.for(LimitedUser, :documents) }

    it 'states the field limits' do
      expect(constraints.error_message(:too_large)).to include('2 KB').or include('2 Ko')
      expect(constraints.error_message(:invalid_type)).to include('.pdf,.jpg,.jpeg')
    end
  end
end
