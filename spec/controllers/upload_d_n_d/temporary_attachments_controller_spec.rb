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
      config.authorization_adapter = :none
    end
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after do
    UploadDND.reset_configuration!
  end

  describe 'GET #index' do
    render_views

    let(:other_session_id) { SecureRandom.uuid }

    def create_temp_attachment(session:, attribute:, filename:)
      temp = UploadDND::TemporaryAttachment.create!(session_id: session, attribute_name: attribute)
      temp.blob.attach(io: StringIO.new("data"), filename: filename, content_type: 'image/png')
      temp
    end

    it 'renders the temporary files of the current session' do
      create_temp_attachment(session: session_id, attribute: 'documents', filename: 'mine.png')

      get :index, params: { attribute_name: 'documents' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="udnd_files_list_documents"')
      expect(response.body).to include('mine.png')
    end

    it 'renders an empty list when the session has no temporary files' do
      get :index, params: { attribute_name: 'documents' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="udnd_files_list_documents"')
      expect(response.body).to include('udnd-no-files')
      expect(response.body).not_to include('udnd-file-item')
    end

    it 'does not leak files from another session' do
      create_temp_attachment(session: other_session_id, attribute: 'documents', filename: 'theirs.png')

      get :index, params: { attribute_name: 'documents' }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('theirs.png')
    end

    it 'only lists files of the requested attribute' do
      create_temp_attachment(session: session_id, attribute: 'avatar', filename: 'avatar.png')

      get :index, params: { attribute_name: 'documents' }

      expect(response.body).not_to include('avatar.png')
    end

    it 'returns 400 without attribute_name' do
      get :index

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 400 with an invalid attribute_name' do
      get :index, params: { attribute_name: 'Documents; DROP' }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'DELETE #purge' do
    def create_temp_attachment(session:, attribute:)
      temp = UploadDND::TemporaryAttachment.create!(session_id: session, attribute_name: attribute)
      temp.blob.attach(io: StringIO.new("data"), filename: 'f.png', content_type: 'image/png')
      temp
    end

    it 'destroys all temporary files of the current session for the attribute and returns 204' do
      create_temp_attachment(session: session_id, attribute: 'documents')
      create_temp_attachment(session: session_id, attribute: 'documents')

      expect {
        delete :purge, params: { attribute_name: 'documents' }
      }.to change(UploadDND::TemporaryAttachment, :count).by(-2)

      expect(response).to have_http_status(:no_content)
    end

    it 'purges the attached blobs' do
      temp = create_temp_attachment(session: session_id, attribute: 'documents')
      blob_id = temp.blob.blob.id

      delete :purge, params: { attribute_name: 'documents' }

      expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
    end

    it 'returns 204 when there is nothing to purge' do
      delete :purge, params: { attribute_name: 'documents' }

      expect(response).to have_http_status(:no_content)
    end

    it 'does not touch files of another session' do
      other = create_temp_attachment(session: SecureRandom.uuid, attribute: 'documents')

      delete :purge, params: { attribute_name: 'documents' }

      expect(UploadDND::TemporaryAttachment.exists?(other.id)).to be(true)
    end

    it 'does not touch files of another attribute' do
      other = create_temp_attachment(session: session_id, attribute: 'avatar')

      delete :purge, params: { attribute_name: 'documents' }

      expect(UploadDND::TemporaryAttachment.exists?(other.id)).to be(true)
    end

    it 'returns 400 without attribute_name' do
      delete :purge

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 400 with an invalid attribute_name' do
      delete :purge, params: { attribute_name: 'Documents; DROP' }

      expect(response).to have_http_status(:bad_request)
    end

    context 'when the authorization policy denies destroy' do
      before do
        # Pundit n'est pas chargé dans la suite : on simule le refus rendu par authorize_delete!
        allow(controller).to receive(:authorize_delete!) do
          controller.send(:render_error, 'denied', :forbidden)
        end
      end

      it 'returns 403 and purges nothing' do
        create_temp_attachment(session: session_id, attribute: 'documents')

        expect {
          delete :purge, params: { attribute_name: 'documents' }
        }.not_to change(UploadDND::TemporaryAttachment, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end
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
        # Le détail de l'exception reste dans les logs.
        expect(response.body).not_to include('boom')
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
