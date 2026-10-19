# frozen_string_literal: true

require 'rails_helper'

# Purge des blobs refusés (DirectUpload : le fichier est déjà dans le bucket
# quand le serveur le contrôle). Chaque chemin d'erreur vérifie le statut de la
# réponse ET le sort du blob.
RSpec.describe UploadDND::TemporaryAttachmentsController, type: :controller do
  include ActiveJob::TestHelper

  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }

  def upload(data: "fake image data", content_type: 'image/png', filename: 'x.png')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type, identify: false)
  end

  def post_blob(blob, attribute_name: 'documents')
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: attribute_name }, format: :json
    end
  end

  def blob_exists?(blob)
    ActiveStorage::Blob.exists?(blob.id)
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = :none
    end
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after { UploadDND.reset_configuration! }

  describe 'rejected uploads are purged' do
    it 'file too large (422)' do
      UploadDND.configuration.max_size = 5
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to be_present
      expect(blob_exists?(blob)).to be false
    end

    it 'type not accepted (422)' do
      blob = upload(content_type: 'application/x-msdownload', filename: 'x.exe')

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be false
    end

    it 'strict MIME: detected type not accepted (422)' do
      UploadDND.configuration.strict_mime_check = true
      UploadDND.configuration.accepted_types = '.png'
      blob = upload(data: "%PDF-1.4\n%fake pdf\n")

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be false
    end

    it 'strict MIME: detected type differs from the declared one (422)' do
      UploadDND.configuration.strict_mime_check = true
      UploadDND.configuration.accepted_types = '.png,.pdf'
      blob = upload(data: "%PDF-1.4\n%fake pdf\n")

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.suspicious_type'))
      expect(blob_exists?(blob)).to be false
    end

    it 'strict MIME: detection failure (422)' do
      UploadDND.configuration.strict_mime_check = true
      allow(Marcel::MimeType).to receive(:for).and_call_original
      allow(Marcel::MimeType).to receive(:for).with(kind_of(String), name: anything).and_raise(StandardError, 'boom')
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be false
    end

    it 'TemporaryAttachment invalid (422)' do
      allow(UploadDND::TemporaryAttachment).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(UploadDND::TemporaryAttachment.new))
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be false
    end

    it 'unexpected exception while saving the temporary file (500), still reported' do
      allow(UploadDND::TemporaryAttachment).to receive(:create!).and_raise(StandardError, 'boom')
      blob = upload

      # L'exception est relancée après la purge : le handler du moteur la journalise.
      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(/StandardError - boom/).and_call_original

      post_blob(blob)

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?(blob)).to be false
    end

    it 'a purge failure does not hide the original error' do
      UploadDND.configuration.max_size = 5
      allow(UploadDND::RejectedBlob).to receive(:discard).and_raise(StandardError, 'purge down')
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq(
        I18n.t('upload_d_n_d.errors.too_large', max_size: ActiveSupport::NumberHelper.number_to_human_size(5))
      )
    end

    it 'a purge failure does not hide the original exception' do
      allow(UploadDND::TemporaryAttachment).to receive(:create!).and_raise(StandardError, 'boom')
      allow(UploadDND::RejectedBlob).to receive(:discard).and_raise(StandardError, 'purge down')
      blob = upload

      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(/StandardError - boom/).and_call_original

      post_blob(blob)

      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe 'blobs that must never be purged' do
    before { UploadDND.configuration.max_size = 5 }

    it 'blob already attached to a record (rejected, 422)' do
      user = User.create!(name: 'Test', email: 'test@example.com')
      blob = upload
      user.avatar.attach(blob)

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be true
      expect(user.reload.avatar).to be_attached
    end

    it 'blob held by another TemporaryAttachment (rejected, 422)' do
      blob = upload
      other = UploadDND::TemporaryAttachment.create!(session_id: 'other', attribute_name: 'documents')
      other.blob.attach(blob)

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be true
      expect(other.reload.blob).to be_attached
    end

    it 'blob older than the purge window (rejected, 422)' do
      blob = upload
      blob.update_column(:created_at, 2.hours.ago)

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(blob_exists?(blob)).to be true
    end
  end

  describe 'requests refused for lack of rights modify nothing' do
    before do
      stub_const('Pundit', Module.new)
      stub_const('Pundit::NotDefinedError', Class.new(StandardError))
      stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
      UploadDND.configure { |config| config.authorization_adapter = :pundit }
      UploadDND.configuration.max_size = 5
    end

    it 'policy refuses (403)' do
      controller.singleton_class.define_method(:authorize) { |*| raise Pundit::NotAuthorizedError }
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:forbidden)
      expect(blob_exists?(blob)).to be true
    end

    # L'autorisation n'a pas abouti : seul un succès explicite autorise la purge,
    # quelle que soit l'exception (autre adaptateur, policy qui plante...).
    it 'authorization raises an unexpected error (500)' do
      controller.singleton_class.define_method(:authorize) { |*| raise StandardError, 'policy crashed' }
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?(blob)).to be true
    end

    it 'policy not defined (fail-closed, 500)' do
      controller.singleton_class.define_method(:authorize) { |*| raise Pundit::NotDefinedError }
      blob = upload

      post_blob(blob)

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?(blob)).to be true
    end
  end

  it 'authentication required (401) modifies nothing' do
    UploadDND.configure { |config| config.require_authentication = true }
    allow(controller).to receive(:current_user).and_return(nil)
    blob = upload

    post_blob(blob)

    expect(response).to have_http_status(:unauthorized)
    expect(blob_exists?(blob)).to be true
  end

  it 'accepted upload keeps the blob and enqueues no purge' do
    blob = upload

    expect {
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'documents' }, format: :json
    }.not_to have_enqueued_job(UploadDND::PurgeRejectedBlobJob)

    expect(response).to have_http_status(:ok)
    expect(blob_exists?(blob)).to be true
  end
end
