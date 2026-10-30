# frozen_string_literal: true

require 'rails_helper'

# Bout en bout avec un vrai cookie de session (pas de stub) : l'id doit rester
# stable entre les requêtes, y compris quand la toute première requête arrive
# sur une session vierge.
RSpec.describe 'Temporary attachments across a real session', type: :request do
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'draft.png', content_type: 'image/png')
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = :none
    end
  end

  after { UploadDND.reset_configuration! }

  def upload!(blob)
    post '/upload_d_n_d/temporary_attachments',
         params: { signed_blob_id: blob.signed_id, target: temp_target_for(User, :documents) }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json', 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  it 'accepts an upload on a pristine session and lists it on the next request' do
    upload!(blob)
    expect(response).to have_http_status(:ok)
    expect(UploadDND::TemporaryAttachment.last.session_id).to be_present

    get '/upload_d_n_d/temporary_attachments', params: { attribute_name: 'documents' }
    expect(response.body).to include('draft.png')
  end

  it 'primes the session on a read-only request so later uploads share the same id' do
    get '/upload_d_n_d/temporary_attachments', params: { attribute_name: 'documents' }
    expect(response.headers['Set-Cookie']).to be_present

    upload!(blob)
    get '/upload_d_n_d/temporary_attachments', params: { attribute_name: 'documents' }
    expect(response.body).to include('draft.png')
  end

  it 'does not leak files to another session' do
    upload!(blob)

    reset!
    get '/upload_d_n_d/temporary_attachments', params: { attribute_name: 'documents' }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('draft.png')
  end
end
