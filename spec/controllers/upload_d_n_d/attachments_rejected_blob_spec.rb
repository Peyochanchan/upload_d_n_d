# frozen_string_literal: true

require 'rails_helper'

# Purge des blobs refusés à l'attachement sur un record existant. Chaque
# chemin d'erreur vérifie le statut de la réponse ET le sort du blob.
RSpec.describe UploadDND::AttachmentsController, type: :controller do
  include ActiveJob::TestHelper

  routes { UploadDND::Engine.routes }

  let(:user) { User.create!(name: 'Test', email: 'test@example.com') }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png')
  end

  def post_blob(attribute_name: 'avatar', record_gid: user.to_global_id.to_s)
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: attribute_name, record_gid: record_gid }, format: :json
    end
  end

  def blob_exists?
    ActiveStorage::Blob.exists?(blob.id)
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = :none
    end
    allow(controller).to receive(:session).and_return({ id: SecureRandom.uuid })
  end

  after { UploadDND.reset_configuration! }

  describe 'rejected uploads are purged' do
    it 'model validation fails (422)' do
      limited = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        def self.name = 'LimitedUser'
        include UploadDND::Uploadable
        uploadable :avatar, max_size: 1
      end
      stub_const('LimitedUser', limited)
      record = LimitedUser.create!(name: 'Test', email: 'test@example.com')

      post_blob(record_gid: record.to_global_id.to_s)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?).to be false
    end

    it 'attribute is not an attachment (422)' do
      post_blob(attribute_name: 'email')

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?).to be false
    end

    it 'record not found (404)' do
      post_blob(record_gid: 'gid://dummy/User/99999')

      expect(response).to have_http_status(:not_found)
      expect(blob_exists?).to be false
    end

    it 'record invalid raised on save (422)' do
      allow_any_instance_of(User).to receive(:save).and_raise(ActiveRecord::RecordInvalid.new(User.new))

      post_blob

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?).to be false
    end

    it 'unexpected exception on save (500), still reported' do
      allow_any_instance_of(User).to receive(:save).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(/StandardError - boom/).and_call_original

      post_blob

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?).to be false
    end
  end

  it 'keeps a blob already attached to another record (rejected, 422)' do
    other = User.create!(name: 'Other', email: 'other@example.com')
    other.avatar.attach(blob)

    post_blob(attribute_name: 'email')

    expect(response).to have_http_status(:unprocessable_content)
    expect(blob_exists?).to be true
    expect(other.reload.avatar).to be_attached
  end

  describe 'requests refused for lack of rights modify nothing' do
    before do
      stub_const('Pundit', Module.new)
      stub_const('Pundit::NotDefinedError', Class.new(StandardError))
      stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
      UploadDND.configure { |config| config.authorization_adapter = :pundit }
    end

    it 'gem policy refuses (403)' do
      controller.singleton_class.define_method(:authorize) { |*| raise Pundit::NotAuthorizedError }

      post_blob

      expect(response).to have_http_status(:forbidden)
      expect(blob_exists?).to be true
    end

    # La policy générique a réussi, celle du record n'a pas abouti : rien
    # n'est purgé.
    it 'record policy raises an unexpected error (500)' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise StandardError, 'policy crashed' if target.is_a?(User)
      end

      post_blob

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?).to be true
    end

    it 'record has no policy: the gem policy alone authorizes the purge (422)' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise Pundit::NotDefinedError if target.is_a?(User)
      end

      post_blob(attribute_name: 'email')

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?).to be false
    end

    it 'record policy refuses (403)' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise Pundit::NotAuthorizedError if target.is_a?(User)
      end

      post_blob

      expect(response).to have_http_status(:forbidden)
      expect(blob_exists?).to be true
    end
  end

  it 'accepted upload keeps the blob and enqueues no purge' do
    expect {
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'avatar', record_gid: user.to_global_id.to_s }, format: :json
    }.not_to have_enqueued_job(UploadDND::PurgeRejectedBlobJob)

    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar).to be_attached
  end
end
