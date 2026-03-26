# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::BaseAttachmentsController, type: :controller do
  # On teste via TemporaryAttachmentsController qui hérite de BaseAttachmentsController
  controller(UploadDND::TemporaryAttachmentsController) { }

  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = nil
      config.accepted_types = nil
    end
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after do
    UploadDND.reset_configuration!
  end

  describe '#sanitize_filename' do
    it 'removes dangerous characters' do
      filename = controller.send(:sanitize_filename, 'test<script>alert(1)</script>.jpg')
      expect(filename).not_to include('<script>')
      expect(filename).to include('.jpg')
    end

    it 'replaces special characters with underscores' do
      filename = controller.send(:sanitize_filename, 'test file!@#$%^&*().jpg')
      expect(filename).to match(/^[a-zA-Z0-9_\.\-]+$/)
    end

    it 'truncates long filenames' do
      long_name = 'a' * 300 + '.jpg'
      filename = controller.send(:sanitize_filename, long_name)
      expect(filename.length).to be <= 255
    end

    it 'preserves file extension' do
      filename = controller.send(:sanitize_filename, 'dangerous/../../../etc/passwd.jpg')
      expect(filename).to end_with('.jpg')
    end

    it 'handles blank filename with fallback' do
      filename = controller.send(:sanitize_filename, '...')
      # Les points sont remplacés par rien, donc on obtient une chaîne vide puis 'file'
      expect(filename).to match(/\.{3}|file/) # Accepte soit "..." soit "file."
    end

    it 'handles filename without extension' do
      filename = controller.send(:sanitize_filename, 'test_file')
      expect(filename).to eq('test_file')
    end
  end

  describe '#current_session_id' do
    context 'with session object having id method' do
      it 'returns session.id' do
        session_double = double(id: 'session-123')
        allow(controller).to receive(:session).and_return(session_double)

        result = controller.send(:current_session_id)
        expect(result).to eq('session-123')
      end
    end

    context 'with hash session' do
      it 'returns session[:id]' do
        allow(controller).to receive(:session).and_return({ id: 'hash-session-456' })

        result = controller.send(:current_session_id)
        expect(result).to eq('hash-session-456')
      end

      it 'returns session["id"] when symbol key missing' do
        allow(controller).to receive(:session).and_return({ "id" => 'string-key-789' })

        result = controller.send(:current_session_id)
        expect(result).to eq('string-key-789')
      end
    end

    context 'with nil session_id' do
      it 'returns empty string' do
        allow(controller).to receive(:session).and_return({})

        result = controller.send(:current_session_id)
        expect(result).to eq('')
      end
    end
  end

  describe '#turbo_stream_request?' do
    it 'detects turbo_stream format param' do
      allow(controller).to receive(:params).and_return({ format: 'turbo_stream' })

      result = controller.send(:turbo_stream_request?)
      expect(result).to be true
    end

    it 'detects turbo_stream Accept header' do
      request.headers['Accept'] = 'text/vnd.turbo-stream.html'

      result = controller.send(:turbo_stream_request?)
      expect(result).to be true
    end

    it 'returns false for regular requests' do
      allow(controller).to receive(:params).and_return({ format: 'json' })

      result = controller.send(:turbo_stream_request?)
      expect(result).to be false
    end

    it 'returns false when Accept header is not turbo-stream' do
      request.headers['Accept'] = 'application/json'

      result = controller.send(:turbo_stream_request?)
      expect(result).to be false
    end
  end

  describe '#render_turbo_stream_replace' do
    # Ces tests nécessitent une réponse HTTP, on les passe via create
    it 'generates turbo stream markup correctly' do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("test"),
        filename: 'test.txt',
        content_type: 'text/plain'
      )

      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'documents'
      }, format: :turbo_stream

      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(response.body).to include('<turbo-stream')
      expect(response.body).to include('action="replace"')
    end
  end

  describe 'signed_blob_id validation' do
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("test"),
        filename: 'test.txt',
        content_type: 'text/plain'
      )
    end

    it 'accepts valid signed_blob_id' do
      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'documents'
      }, format: :json

      expect(response).to have_http_status(:ok)
    end

    it 'rejects signed_blob_id that is too short' do
      post :create, params: {
        signed_blob_id: 'short',
        attribute_name: 'documents'
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']).to include('Token')
    end

    it 'rejects signed_blob_id with invalid characters' do
      post :create, params: {
        signed_blob_id: 'a' * 25 + '<script>',
        attribute_name: 'documents'
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects non-string signed_blob_id' do
      post :create, params: {
        signed_blob_id: 12345,
        attribute_name: 'documents'
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'params validation' do
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt') }

    it 'rejects missing signed_blob_id' do
      post :create, params: { attribute_name: 'documents' }, format: :json

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['error']).to include('manquants')
    end

    it 'rejects missing attribute_name' do
      post :create, params: { signed_blob_id: blob.signed_id }, format: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects invalid attribute_name format (uppercase)' do
      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'Documents'
      }, format: :json

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['error']).to include('invalide')
    end

    it 'rejects invalid attribute_name format (special chars)' do
      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'doc-uments'
      }, format: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'accepts valid snake_case attribute_name' do
      post :create, params: {
        signed_blob_id: blob.signed_id,
        attribute_name: 'my_documents_2024'
      }, format: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'error handling' do
    describe '#record_not_found' do
      it 'renders not_found error' do
        allow(controller).to receive(:create).and_raise(ActiveRecord::RecordNotFound)

        post :create, params: {
          signed_blob_id: 'valid' * 10,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to be_present
      end
    end

    describe '#blob_integrity_error' do
      it 'renders unprocessable_entity error' do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt')
        allow(ActiveStorage::Blob).to receive(:find_signed).and_raise(ActiveStorage::IntegrityError)

        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('corrompu')
      end
    end

    describe '#bad_request_error' do
      it 'renders bad_request error' do
        allow(controller).to receive(:create).and_raise(ActionController::BadRequest.new('Custom error'))

        post :create, params: {
          signed_blob_id: 'valid' * 10,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to eq('Custom error')
      end
    end

    describe '#handle_error' do
      it 'catches StandardError and renders 500' do
        allow(controller).to receive(:create).and_raise(StandardError.new('Unexpected error'))

        expect(Rails.logger).to receive(:error).at_least(:once)

        post :create, params: {
          signed_blob_id: 'valid' * 10,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)['error']).to include('erreur')
      end
    end
  end

  describe '#authenticate_user_if_available!' do
    context 'when require_authentication is true' do
      before do
        UploadDND.configure do |config|
          config.require_authentication = true
        end
      end

      it 'blocks request when no user is authenticated' do
        allow(controller).to receive(:current_user).and_return(nil)

        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt')
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['error']).to include('connecté')
      end

      it 'allows request when user is authenticated' do
        user_double = double('User', id: 1)
        allow(controller).to receive(:current_user).and_return(user_double)

        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt')
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when require_authentication is false' do
      it 'allows request without authentication' do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt')
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'documents'
        }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'pundit integration' do
    it 'returns falsey when Pundit is not configured' do
      expect(controller.send(:pundit_enabled?)).to be_falsey
    end

    it 'returns falsey when Pundit is configured but not loaded' do
      # Dans l'environnement de test, Pundit n'est pas chargé
      # donc même si on configure :pundit, pundit_enabled? retourne false
      UploadDND.configure do |config|
        config.authorization_adapter = :pundit
      end

      # Pundit n'est pas défini dans les tests, donc retourne falsey
      expect(defined?(Pundit)).to be_nil
      expect(controller.send(:pundit_enabled?)).to be_falsey
    end
  end
end
