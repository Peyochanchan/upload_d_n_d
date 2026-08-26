# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::SessionId do
  describe '.for' do
    it 'returns the session id as a string' do
      session = { id: 'abc' }
      expect(described_class.for(session)).to eq('abc')
    end

    it 'primes the session so that an id is generated and persisted' do
      session = { id: 'abc' }
      described_class.for(session)
      expect(session[described_class::KEY]).to be(true)
    end

    it 'does not overwrite the priming key' do
      session = { id: 'abc', described_class::KEY => 'kept' }
      described_class.for(session)
      expect(session[described_class::KEY]).to eq('kept')
    end

    it 'prefers #id when the session responds to it' do
      session = double('session', id: 'from-id', :[] => nil, :[]= => nil)
      expect(described_class.for(session)).to eq('from-id')
    end

    it 'returns an empty string for a nil session' do
      expect(described_class.for(nil)).to eq('')
    end
  end
end
