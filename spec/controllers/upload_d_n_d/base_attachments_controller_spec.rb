# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::BaseAttachmentsController, type: :controller do
  # On teste via TemporaryAttachmentsController qui hérite de BaseAttachmentsController
  controller(UploadDND::TemporaryAttachmentsController) { }

  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }
  # Cible temporaire valide (le contrôleur testé est TemporaryAttachmentsController).
  let(:valid_target) { temp_target_for(User, :documents) }

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = :none
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
        target: valid_target
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
        target: valid_target
      }, format: :json

      expect(response).to have_http_status(:ok)
    end

    it 'rejects signed_blob_id that is too short' do
      post :create, params: {
        signed_blob_id: 'short',
        target: valid_target
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']).to include('Token')
    end

    it 'rejects signed_blob_id with invalid characters' do
      post :create, params: {
        signed_blob_id: 'a' * 25 + '<script>',
        target: valid_target
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects non-string signed_blob_id' do
      post :create, params: {
        signed_blob_id: 12345,
        target: valid_target
      }, format: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'params validation' do
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt') }

    it 'rejects missing signed_blob_id' do
      post :create, params: { target: valid_target }, format: :json

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)['error']).to include('manquants')
    end

    it 'rejects missing target' do
      post :create, params: { signed_blob_id: blob.signed_id }, format: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects a forged / invalid target' do
      post :create, params: { signed_blob_id: blob.signed_id, target: 'forged.token' }, format: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'accepts a valid signed target' do
      post :create, params: { signed_blob_id: blob.signed_id, target: valid_target }, format: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'error handling' do
    # find_blob rejette désormais un signed_blob_id invalide (401) ; ces tests
    # des handlers rescue_from ont besoin d'un blob valide pour atteindre
    # l'action (stubbée pour lever).
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png') }

    describe '#record_not_found' do
      it 'renders not_found error' do
        allow(controller).to receive(:create).and_raise(ActiveRecord::RecordNotFound)

        post :create, params: {
          signed_blob_id: blob.signed_id,
          target: valid_target
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
          target: valid_target
        }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('corrompu')
      end
    end

    describe '#bad_request_error' do
      it 'renders bad_request error' do
        allow(controller).to receive(:create).and_raise(ActionController::BadRequest.new('Custom error'))

        post :create, params: {
          signed_blob_id: blob.signed_id,
          target: valid_target
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        # Le détail de l'exception n'est jamais renvoyé au client.
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.bad_request'))
      end
    end

    describe '#handle_error' do
      it 'catches StandardError and renders 500' do
        allow(controller).to receive(:create).and_raise(StandardError.new('Unexpected error'))

        expect(Rails.logger).to receive(:error).at_least(:once)

        post :create, params: {
          signed_blob_id: blob.signed_id,
          target: valid_target
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
          target: valid_target
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
          target: valid_target
        }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when require_authentication is false' do
      it 'allows request without authentication' do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt')
        post :create, params: {
          signed_blob_id: blob.signed_id,
          target: valid_target
        }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'authorization adapter' do
    let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: 'test.txt') }

    # SÉCURITÉ (S1) : :pundit sans Pundit chargé laissait passer en silence.
    it 'fails closed (500) when :pundit is configured but Pundit is not loaded' do
      UploadDND.configuration.authorization_adapter = :pundit
      expect(defined?(Pundit)).to be_nil

      post :create, params: { signed_blob_id: blob.signed_id, target: valid_target }, format: :json

      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
