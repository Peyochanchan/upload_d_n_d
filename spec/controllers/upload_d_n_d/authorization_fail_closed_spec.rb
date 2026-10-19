# frozen_string_literal: true

require 'rails_helper'

# SÉCURITÉ (S1) : sans adaptateur d'autorisation utilisable, chaque endpoint
# du moteur refuse (403) et ne modifie rien. Auparavant, tout passait.
RSpec.shared_context 'upload_d_n_d authorization' do
  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }
  let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

  def upload
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png')
  end

  before do
    UploadDND.configuration.require_authentication = false
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after { UploadDND.reset_configuration! }
end

UNUSABLE_ADAPTERS = { 'nil (nothing detected)' => nil, 'an unknown value' => :custom }.freeze

RSpec.describe UploadDND::AttachmentsController, type: :controller do
  include_context 'upload_d_n_d authorization'

  UNUSABLE_ADAPTERS.each do |label, value|
    context "with authorization_adapter = #{label}" do
      before { UploadDND.configuration.authorization_adapter = value }

      it 'refuses create (403), attaches nothing and keeps the blob' do
        blob = upload

        post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(user.reload.avatar).not_to be_attached
        expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      end

      it 'refuses destroy (403) and keeps the file' do
        user.avatar.attach(upload)

        delete :destroy, params: { id: user.avatar.attachment.id, record_gid: user.to_global_id.to_s, attribute_name: 'avatar' }, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(user.reload.avatar).to be_attached
      end
    end
  end

  context 'with authorization_adapter = :none' do
    before { UploadDND.configuration.authorization_adapter = :none }

    it 'lets create through' do
      post :create, params: { signed_blob_id: upload.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }, format: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar).to be_attached
    end
  end

  context 'with authorization_adapter = :cancancan' do
    before do
      stub_const('CanCan::AccessDenied', Class.new(StandardError))
      UploadDND.configuration.authorization_adapter = :cancancan
    end

    it 'checks the generic rule then the record' do
      calls = []
      controller.singleton_class.define_method(:authorize!) { |action, subject| calls << [ action, subject ] }

      post :create, params: { signed_blob_id: upload.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }, format: :json

      expect(response).to have_http_status(:ok)
      expect(calls).to eq([ [ :create, :upload_d_n_d_attachment ], [ :update, user ] ])
    end

    it 'refuses (403) when the ability denies the record' do
      owner = user
      controller.singleton_class.define_method(:authorize!) { |_action, subject| raise CanCan::AccessDenied if subject == owner }

      post :create, params: { signed_blob_id: upload.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.avatar).not_to be_attached
    end

    it 'refuses destroy (403) without falling back to the generic rule' do
      user.avatar.attach(upload)
      calls = []
      controller.singleton_class.define_method(:authorize!) do |action, subject|
        calls << [ action, subject ]
        raise CanCan::AccessDenied
      end

      delete :destroy, params: { id: user.avatar.attachment.id, record_gid: user.to_global_id.to_s, attribute_name: 'avatar' }, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(calls).to eq([ [ :update, user ] ])
      expect(user.reload.avatar).to be_attached
    end
  end
end

RSpec.describe UploadDND::TemporaryAttachmentsController, type: :controller do
  include_context 'upload_d_n_d authorization'

  def temporary_file
    UploadDND::TemporaryAttachment.create!(session_id: UploadDND::SessionId.for(controller.session), attribute_name: 'documents').tap do |temp|
      temp.blob.attach(upload)
    end
  end

  UNUSABLE_ADAPTERS.each do |label, value|
    context "with authorization_adapter = #{label}" do
      before { UploadDND.configuration.authorization_adapter = value }

      it 'refuses create (403), creates nothing and keeps the blob' do
        blob = upload

        expect {
          post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'documents' }, format: :json
        }.not_to change(UploadDND::TemporaryAttachment, :count)

        expect(response).to have_http_status(:forbidden)
        expect(ActiveStorage::Blob.exists?(blob.id)).to be true
      end

      it 'refuses destroy (403) and keeps the temporary file' do
        temp = temporary_file

        delete :destroy, params: { id: temp.id }, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(UploadDND::TemporaryAttachment.exists?(temp.id)).to be true
      end

      it 'refuses purge (403) and keeps the temporary files' do
        temp = temporary_file

        delete :purge, params: { attribute_name: 'documents' }, format: :json

        expect(response).to have_http_status(:forbidden)
        expect(UploadDND::TemporaryAttachment.exists?(temp.id)).to be true
      end
    end
  end

  context 'with authorization_adapter = :none' do
    before { UploadDND.configuration.authorization_adapter = :none }

    it 'lets create through' do
      post :create, params: { signed_blob_id: upload.signed_id, attribute_name: 'documents' }, format: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
