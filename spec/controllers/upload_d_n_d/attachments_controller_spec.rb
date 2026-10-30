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
      config.authorization_adapter = :none
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
        { signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar) }
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
        { signed_blob_id: blob.signed_id, target: signed_target_for(user, :documents) }
      end

      it 'attaches the blob to the collection' do
        expect {
          post :create, params: valid_params, format: :turbo_stream
        }.to change { user.reload.documents.count }.by(1)
      end
    end

    context 'with invalid params' do
      it 'returns bad_request when target is missing' do
        post :create, params: { signed_blob_id: blob.signed_id }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns bad_request when signed_blob_id is missing' do
        post :create, params: { target: signed_target_for(user, :avatar) }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to be_present
      end

      it 'returns bad_request for a forged / invalid target' do
        post :create, params: { signed_blob_id: blob.signed_id, target: 'forged.token.value' }, format: :json

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns unauthorized for invalid blob signature' do
        post :create, params: {
          signed_blob_id: 'a' * 40, target: signed_target_for(user, :avatar)
        }, format: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns not_found when the signed record does not exist' do
        target = UploadDND::SignedTarget.generate(User, :avatar, record_id: 99_999)
        post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :json

        expect(response).to have_http_status(:not_found)
      end

      # F3 : un attribut non déclaré `uploadable` ne peut pas être ciblé — le
      # jeton est rejeté à la vérification (400), le record n'est pas touché.
      it 'refuses a token for a non-uploadable attachment (400)' do
        target = UploadDND::SignedTarget.generate(User, :internal_file)
        post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :json

        expect(response).to have_http_status(:bad_request)
        expect(user.reload.internal_file).not_to be_attached
      end

      # SÉCURITÉ : attribute_name ne doit jamais servir à appeler une méthode
      # quelconque sur le record. Un jeton pour une telle « méthode » n'est pas
      # un attribut `uploadable` et est refusé à la vérification.
      %w[destroy delete touch reload email].each do |method_name|
        it "refuses #{method_name} (not an uploadable attribute) without calling it" do
          expect_any_instance_of(User).not_to receive(method_name)

          target = UploadDND::SignedTarget.generate(User, method_name)
          post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :json

          expect(response).to have_http_status(:bad_request)
          expect(User.exists?(user.id)).to be true
        end
      end

      it 'does not render the files list when the target is refused' do
        target = UploadDND::SignedTarget.generate(User, :internal_file)
        post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :turbo_stream

        expect(response.body).not_to include('udnd_files_list')
      end
    end

    context 'authorization with Pundit' do
      before do
        stub_const('Pundit', Module.new)
        stub_const('Pundit::NotDefinedError', Class.new(StandardError))
        stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
        UploadDND.configure { |config| config.authorization_adapter = :pundit }
        request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      end

      let(:valid_params) do
        { signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar) }
      end

      it 'authorizes on the record policy (update?) only' do
        calls = []
        controller.singleton_class.define_method(:authorize) { |target, query| calls << [ target, query ] }

        post :create, params: valid_params, format: :turbo_stream

        expect(calls).to eq([ [ user, :update? ] ])
        expect(user.reload.avatar).to be_attached
      end

      it 'renders forbidden, attaches nothing and leaks no files list when the record policy refuses' do
        controller.singleton_class.define_method(:authorize) do |target, _query|
          raise Pundit::NotAuthorizedError if target.is_a?(User)
        end

        post :create, params: valid_params, format: :turbo_stream

        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include('udnd_files_list')
        expect(user.reload.avatar).not_to be_attached
      end

      # Fail-closed : pas de policy pour le record → refus (plus de repli sur
      # une policy générique).
      it 'denies (403) and attaches nothing when the record has no policy' do
        controller.singleton_class.define_method(:authorize) do |target, _query|
          raise Pundit::NotDefinedError if target.is_a?(User)
        end

        post :create, params: valid_params, format: :turbo_stream

        expect(response).to have_http_status(:forbidden)
        expect(user.reload.avatar).not_to be_attached
      end
    end

    context 'with JSON format' do
      let(:valid_params) do
        { signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar) }
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
          signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar)
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to include('Name is too short')
      end
    end
  end

  describe 'DELETE #destroy' do
    before do
      request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      user.avatar.attach(blob)
    end

    let(:attachment) { user.avatar_attachment }
    let(:valid_params) do
      { id: attachment.id, target: signed_target_for(user, :avatar) }
    end

    it 'detaches the file from the record' do
      expect {
        delete :destroy, params: valid_params, format: :turbo_stream
      }.to change { user.reload.avatar.attached? }.from(true).to(false)
    end

    it 'returns a turbo stream response replacing the files list' do
      delete :destroy, params: valid_params, format: :turbo_stream

      expect(response.content_type).to include('text/vnd.turbo-stream.html')
      expect(response.body).to include('udnd_files_list_avatar')
    end

    it 'calls the on_file_removed callback' do
      calls = []
      UploadDND.configure do |config|
        config.on_file_removed = ->(record, attribute_name, current_user) { calls << [ record, attribute_name ] }
      end

      delete :destroy, params: valid_params, format: :turbo_stream

      expect(calls).to eq([ [ user, 'avatar' ] ])
    end

    context 'security checks' do
      it 'refuses when the attachment belongs to another record' do
        other_user = create(:user)
        other_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("other"), filename: 'other.png', content_type: 'image/png'
        )
        other_user.avatar.attach(other_blob)

        delete :destroy, params: {
          id: other_user.avatar_attachment.id, target: signed_target_for(user, :avatar)
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(other_user.reload.avatar.attached?).to be true
      end

      it 'refuses when the target attribute does not match the attachment' do
        delete :destroy, params: {
          id: attachment.id, target: signed_target_for(user, :documents)
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(user.reload.avatar.attached?).to be true
      end

      it 'returns not_found when the signed record does not exist' do
        target = UploadDND::SignedTarget.generate(User, :avatar, record_id: 99_999)
        delete :destroy, params: { id: attachment.id, target: target }, format: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns bad_request when target is missing' do
        delete :destroy, params: { id: attachment.id }, format: :json

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns bad_request for a forged / invalid target' do
        delete :destroy, params: { id: attachment.id, target: 'forged' }, format: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'authorization with Pundit' do
      before do
        stub_const('Pundit', Module.new)
        stub_const('Pundit::NotDefinedError', Class.new(StandardError))
        stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
        UploadDND.configure { |config| config.authorization_adapter = :pundit }
      end

      it 'authorizes via the record policy (update?) only' do
        calls = []
        controller.singleton_class.define_method(:authorize) { |target, query| calls << [ target, query ] }

        delete :destroy, params: valid_params, format: :turbo_stream

        expect(calls).to eq([ [ user, :update? ] ])
      end

      # Fail-closed : pas de policy pour le record → refus, fichier conservé.
      it 'denies (403) and keeps the file when the record has no policy' do
        controller.singleton_class.define_method(:authorize) do |target, _query|
          raise Pundit::NotDefinedError if target.is_a?(User)
        end

        delete :destroy, params: valid_params, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(user.reload.avatar.attached?).to be true
      end

      it 'renders forbidden and keeps the file when not authorized' do
        controller.singleton_class.define_method(:authorize) do |_target, _query|
          raise Pundit::NotAuthorizedError
        end

        delete :destroy, params: valid_params, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(user.reload.avatar.attached?).to be true
      end
    end
  end

  describe 'error handling' do
    it 'handles ActiveRecord::RecordNotFound from the blob lookup' do
      allow(ActiveStorage::Blob).to receive(:find_signed).and_raise(ActiveRecord::RecordNotFound)

      post :create, params: {
        signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar)
      }, format: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'handles an unexpected error gracefully (500)' do
      allow(User).to receive(:find).and_raise(StandardError, "Test error")

      post :create, params: {
        signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar)
      }, format: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)['error']).to include('erreur')
    end

    it 'handles RecordInvalid errors' do
      allow_any_instance_of(User).to receive(:save).and_raise(
        ActiveRecord::RecordInvalid.new(User.new)
      )

      post :create, params: {
        signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar)
      }, format: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
