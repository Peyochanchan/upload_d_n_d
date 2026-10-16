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
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.blob_not_found'))
      end

      it 'returns error when attribute does not exist on record' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'nonexistent_attribute',
          record_gid: user.to_global_id.to_s
        }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.invalid_attribute', attribute: 'nonexistent_attribute'))
      end

      # SÉCURITÉ : attribute_name ne doit jamais servir à appeler une méthode
      # quelconque sur le record (respond_to? + send laissait passer destroy).
      %w[destroy delete touch reload email].each do |method_name|
        it "refuses #{method_name} (not an attachment) without calling it" do
          expect_any_instance_of(User).not_to receive(method_name)

          post :create, params: {
            signed_blob_id: blob.signed_id,
            attribute_name: method_name,
            record_gid: user.to_global_id.to_s
          }, format: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(User.exists?(user.id)).to be true
        end
      end

      it 'does not render the files list of the record when the attribute is refused' do
        post :create, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'destroy',
          record_gid: user.to_global_id.to_s
        }, format: :turbo_stream

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
        { signed_blob_id: blob.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }
      end

      it 'checks the gem policy (create?) then the record policy (update?)' do
        calls = []
        controller.singleton_class.define_method(:authorize) { |target, query| calls << [ target, query ] }

        post :create, params: valid_params, format: :turbo_stream

        expect(calls).to eq([ [ :upload_d_n_d_attachment, :create? ], [ user, :update? ] ])
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

      it 'relies on the gem policy alone when the record has no policy' do
        controller.singleton_class.define_method(:authorize) do |target, _query|
          raise Pundit::NotDefinedError if target.is_a?(User)
        end

        post :create, params: valid_params, format: :turbo_stream

        expect(response).to have_http_status(:ok)
        expect(user.reload.avatar).to be_attached
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

  describe 'DELETE #destroy' do
    before do
      request.headers['Accept'] = 'text/vnd.turbo-stream.html'
      user.avatar.attach(blob)
    end

    let(:attachment) { user.avatar_attachment }
    let(:valid_params) do
      {
        id: attachment.id,
        record_gid: user.to_global_id.to_s,
        attribute_name: 'avatar'
      }
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
          id: other_user.avatar_attachment.id,
          record_gid: user.to_global_id.to_s,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(other_user.reload.avatar.attached?).to be true
      end

      it 'refuses when attribute_name does not match the attachment' do
        delete :destroy, params: valid_params.merge(attribute_name: 'documents'), format: :json

        expect(response).to have_http_status(:not_found)
        expect(user.reload.avatar.attached?).to be true
      end

      it 'returns not_found when the record does not exist' do
        delete :destroy, params: valid_params.merge(record_gid: 'gid://dummy/User/99999'), format: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns bad_request when record_gid is missing' do
        delete :destroy, params: { id: attachment.id, attribute_name: 'avatar' }, format: :json

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns bad_request for invalid attribute_name format' do
        delete :destroy, params: valid_params.merge(attribute_name: 'Invalid-Name!'), format: :json

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

      it 'authorizes via the record policy (update?)' do
        calls = []
        controller.singleton_class.define_method(:authorize) { |target, query| calls << [ target, query ] }

        delete :destroy, params: valid_params, format: :turbo_stream

        expect(calls).to eq([ [ user, :update? ] ])
      end

      it 'falls back to the gem policy when the record has no policy' do
        calls = []
        controller.singleton_class.define_method(:authorize) do |target, query|
          calls << [ target, query ]
          raise Pundit::NotDefinedError if target.is_a?(User)
        end

        delete :destroy, params: valid_params, format: :turbo_stream

        expect(calls).to eq([ [ user, :update? ], [ :upload_d_n_d_attachment, :destroy? ] ])
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
