# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::TemporaryAttachmentsController, type: :controller do
  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image data"),
      filename: 'test.png',
      content_type: 'image/png'
    )
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = nil
    end
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after do
    UploadDND.reset_configuration!
  end

  describe 'POST #create' do
    context 'with valid params' do
      before do
        request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      end

      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }
      end

      it 'creates a temporary attachment' do
        expect {
          post :create, params: valid_params, format: :turbo_stream
        }.to change(UploadDND::TemporaryAttachment, :count).by(1)
      end

      it 'sets the correct session_id' do
        post :create, params: valid_params, format: :turbo_stream

        temp_attachment = UploadDND::TemporaryAttachment.last
        expect(temp_attachment.session_id).to eq(session_id)
      end

      it 'sets the correct attribute_name' do
        post :create, params: valid_params, format: :turbo_stream

        temp_attachment = UploadDND::TemporaryAttachment.last
        expect(temp_attachment.attribute_name).to eq('avatar')
      end

      it 'attaches the blob to the temporary attachment' do
        post :create, params: valid_params, format: :turbo_stream

        temp_attachment = UploadDND::TemporaryAttachment.last
        expect(temp_attachment.blob).to be_attached
        expect(temp_attachment.blob.blob).to eq(blob)
      end

      it 'returns a turbo stream response' do
        post :create, params: valid_params, format: :turbo_stream
        expect(response.content_type).to include('text/vnd.turbo-stream.html')
      end

      it 'sanitizes the filename' do
        blob.update(filename: 'test<script>alert(1)</script>.png')
        post :create, params: valid_params, format: :turbo_stream

        expect(blob.reload.filename.to_s).not_to include('<script>')
      end
    end

    context 'with invalid params' do
      it 'returns error when signed_blob_id is missing' do
        post :create, params: { attribute_name: 'avatar' }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns error when attribute_name is missing' do
        post :create, params: { signed_blob_id: blob.signed_id }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns error for invalid attribute_name format' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'Invalid-Name!'
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('invalide')
      end

      it 'returns error for invalid blob signature' do
        post :create, params: {
          signed_blob_id: 'invalid_signature',
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with JSON format' do
      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }
      end

      it 'returns JSON response' do
        post :create, params: valid_params, format: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('ok')
      end
    end

    context 'with server-side validation' do
      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }
      end

      it 'rejects invalid content types based on configuration' do
        UploadDND.configure do |config|
          config.accepted_types = 'image/jpeg'
        end

        post :create, params: valid_params, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('Type de fichier non accepté')
      end

      it 'rejects suspicious types when strict_mime_check is enabled' do
        # Force la création du blob AVANT le stub Marcel
        signed_id = blob.signed_id

        UploadDND.configure do |config|
          config.accepted_types = 'image/png,image/jpeg'
          config.strict_mime_check = true
        end

        # Marcel détecte image/jpeg mais le blob déclare image/png → suspicion de spoofing
        allow(Marcel::MimeType).to receive(:for).and_return('image/jpeg')

        post :create, params: { signed_blob_id: signed_id, attribute_name: 'avatar' }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('type réel du fichier')
      end

      it 'returns a clear error when mime detection fails' do
        # Force la création du blob AVANT le stub
        signed_id = blob.signed_id

        UploadDND.configure do |config|
          config.accepted_types = 'image/png'
          config.strict_mime_check = true
        end

        allow(Marcel::MimeType).to receive(:for).and_raise(StandardError, 'boom')

        post :create, params: { signed_blob_id: signed_id, attribute_name: 'avatar' }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('Impossible de vérifier le type de fichier')
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:temp_attachment) do
      create(:temporary_attachment, session_id: session_id, attribute_name: 'avatar')
    end

    context 'with valid session' do
      before do
        request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      end

      it 'destroys the temporary attachment' do
        expect {
          delete :destroy, params: { id: temp_attachment.id }, format: :turbo_stream
        }.to change(UploadDND::TemporaryAttachment, :count).by(-1)
      end

      it 'returns a turbo stream response' do
        delete :destroy, params: { id: temp_attachment.id }, format: :turbo_stream
        expect(response.content_type).to include('text/vnd.turbo-stream.html')
      end
    end

    context 'with invalid session' do
      let!(:other_temp_attachment) do
        create(:temporary_attachment, session_id: 'other_session', attribute_name: 'avatar')
      end

      it 'does not destroy attachment from another session' do
        expect {
          delete :destroy, params: { id: other_temp_attachment.id }, format: :json
        }.not_to change(UploadDND::TemporaryAttachment, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with non-existent attachment' do
      it 'returns not found error' do
        delete :destroy, params: { id: 99999 }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to be_present
      end
    end
  end

  describe 'error handling' do
    it 'handles ActiveRecord::RecordNotFound' do
      allow(ActiveStorage::Blob).to receive(:find_signed).and_raise(ActiveRecord::RecordNotFound)

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar'
      }, format: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'handles StandardError gracefully' do
      allow(UploadDND::TemporaryAttachment).to receive(:create!).and_raise(StandardError, "Test error")

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar'
      }, format: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['error']).to include('erreur')
    end

    it 'handles RecordInvalid errors' do
      allow(UploadDND::TemporaryAttachment).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(UploadDND::TemporaryAttachment.new)
      )

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar'
      }, format: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
