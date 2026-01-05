# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::AttachmentsController, type: :controller do
  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }
  let(:user) { create(:user) }
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
    context 'with valid params and existing record' do
      before do
        request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      end

      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar',
          record_gid: user.to_global_id.to_s
        }
      end

      it 'attaches the blob to the record' do
        expect {
          post :create, params: valid_params, format: :turbo_stream
        }.to change { user.reload.avatar.attached? }.from(false).to(true)
      end

      it 'does not create a temporary attachment' do
        expect {
          post :create, params: valid_params, format: :turbo_stream
        }.not_to change(UploadDND::TemporaryAttachment, :count)
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

      it 'saves the record with validations' do
        post :create, params: valid_params, format: :turbo_stream
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with has_many attachments' do
      before do
        request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      end

      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'documents',
          record_gid: user.to_global_id.to_s,
          multiple: 'true'
        }
      end

      it 'attaches the blob to the collection' do
        expect {
          post :create, params: valid_params, format: :turbo_stream
        }.to change { user.reload.documents.count }.by(1)
      end
    end

    context 'with invalid params' do
      it 'returns error when record_gid is missing' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('record_gid')
        expect(JSON.parse(response.body)['error']).to include('temporary_attachments')
      end

      it 'returns error when signed_blob_id is missing' do
        post :create, params: {
          attribute_name: 'avatar',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns error when attribute_name is missing' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns error for invalid attribute_name format' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'Invalid-Name!',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to include('invalide')
      end

      it 'returns error for invalid blob signature' do
        post :create, params: {
          signed_blob_id: 'invalid_signature',
          attribute_name: 'avatar',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns error when record does not exist' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar',
          record_gid: 'gid://app/User/99999'
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to include('non trouvé')
      end

      it 'returns error when attribute does not exist on record' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'nonexistent_attribute',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to include('inexistant')
      end
    end

    context 'with JSON format' do
      let(:valid_params) do
        {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar',
          record_gid: user.to_global_id.to_s
        }
      end

      it 'returns JSON response' do
        post :create, params: valid_params, format: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['status']).to eq('ok')
      end
    end

    context 'when record validation fails' do
      before do
        allow_any_instance_of(User).to receive(:save).and_return(false)
        errors_double = double('errors').as_null_object
        allow(errors_double).to receive(:full_messages).and_return([ 'Name is too short' ])
        allow_any_instance_of(User).to receive(:errors).and_return(errors_double)
      end

      it 'returns validation error' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to include('Name is too short')
      end
    end
  end

  describe 'error handling' do
    it 'handles ActiveRecord::RecordNotFound' do
      allow(ActiveStorage::Blob).to receive(:find_signed).and_raise(ActiveRecord::RecordNotFound)

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar',
        record_gid: user.to_global_id.to_s
      }, format: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'handles StandardError gracefully' do
      allow(GlobalID::Locator).to receive(:locate).and_raise(StandardError, "Test error")

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar',
        record_gid: user.to_global_id.to_s
      }, format: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['error']).to include('erreur')
    end

    it 'handles RecordInvalid errors' do
      allow_any_instance_of(User).to receive(:save).and_raise(
        ActiveRecord::RecordInvalid.new(User.new)
      )

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'avatar',
        record_gid: user.to_global_id.to_s
      }, format: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
