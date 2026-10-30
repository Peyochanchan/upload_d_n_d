# frozen_string_literal: true

require 'rails_helper'

# A2 : le serveur applique les limites du champ (uploadable) dès le dépôt, et
# purge le blob refusé. Les limites sont dérivées de la cible signée.
RSpec.shared_context 'field constraints' do
  include ActiveJob::TestHelper

  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }

  def upload(data: "x" * 5, content_type: 'image/png', filename: 'x.png')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type, identify: false)
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = :none
    end
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after { UploadDND.reset_configuration! }
end

RSpec.describe UploadDND::TemporaryAttachmentsController, type: :controller do
  include_context 'field constraints'

  def post_blob(blob, target: temp_target_for(LimitedUser, :avatar))
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :json
    end
  end

  context 'with a signed target' do
    it 'refuses a file over the field limit (422) and purges it' do
      blob = upload(data: "x" * 11) # avatar : 10 octets

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to include(ActiveSupport::NumberHelper.number_to_human_size(10))
      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'refuses a type the field does not accept (422)' do
      blob = upload(content_type: 'image/jpeg', filename: 'x.jpg') # avatar : png seulement

      post_blob(blob)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # Cas réel : limites du champ plus larges que la configuration globale.
    it 'accepts a file within the field limits but outside the global ones' do
      UploadDND.configuration.max_size = 5
      UploadDND.configuration.accepted_types = '.png'
      blob = upload(data: "x" * 100, content_type: 'application/pdf', filename: 'x.pdf')

      post_blob(blob, target: temp_target_for(LimitedUser, :documents))

      expect(response).to have_http_status(:ok)
      expect(UploadDND::TemporaryAttachment.for_session(UploadDND::SessionId.for(controller.session)).count).to eq(1)
    end
  end

  context 'with an invalid target' do
    # Rejet AVANT l'autorisation (cible forgée) → 400, et le blob n'est pas purgé.
    it 'refuses a forged target (400) and keeps the blob' do
      blob = upload

      post_blob(blob, target: 'forged')

      expect(response).to have_http_status(:bad_request)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it 'requires a target (400 when missing)' do
      post :create, params: { signed_blob_id: upload.signed_id }, format: :json

      expect(response).to have_http_status(:bad_request)
    end
  end
end

RSpec.describe UploadDND::AttachmentsController, type: :controller do
  include_context 'field constraints'

  let(:user) { LimitedUser.create!(name: 'Test', email: 'test@example.com') }

  def post_blob(blob, record: user, attribute: :avatar)
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, target: signed_target_for(record, attribute) }, format: :json
    end
  end

  it 'refuses a file over the field limit before attaching it (422) and purges it' do
    blob = upload(data: "x" * 11)

    post_blob(blob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.avatar).not_to be_attached
    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
  end

  it 'accepts a file within the field limits' do
    post_blob(upload)

    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar).to be_attached
  end

  # Un champ `uploadable` sans limites propres retombe sur la configuration
  # globale (appliquée dès le dépôt sur un record existant).
  it 'applies the global limits to a bare uploadable field' do
    UploadDND.configuration.max_size = 5
    plain = User.create!(name: 'Plain', email: 'plain@example.com')
    blob = upload(data: "x" * 6, content_type: 'application/x-msdownload', filename: 'x.exe')

    post_blob(blob, record: plain)

    expect(response).to have_http_status(:unprocessable_content)
    expect(plain.reload.avatar).not_to be_attached
  end
end

RSpec.describe 'Transfer of temporary files to the record' do
  include ActiveJob::TestHelper

  let(:session_id) { 'sid' }

  def temporary(attribute_name, data:, content_type: 'image/png', filename: 'x.png')
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type, identify: false)
    UploadDND::TemporaryAttachment.create!(session_id: session_id, attribute_name: attribute_name).tap { |temp| temp.blob.attach(blob) }
  end

  it 'drops a file over the field limits on create (Uploadable#attach_temporary_uploads)' do
    too_large = temporary('avatar', data: "x" * 11)
    fine = temporary('documents', data: "%PDF", content_type: 'application/pdf', filename: 'x.pdf')

    user = perform_enqueued_jobs do
      LimitedUser.create!(name: 'New', email: 'new@example.com', temp_upload_session_id: session_id)
    end

    expect(user.avatar).not_to be_attached
    expect(user.documents.count).to eq(1)
    expect(UploadDND::TemporaryAttachment.exists?(too_large.id)).to be false
    expect(UploadDND::TemporaryAttachment.exists?(fine.id)).to be false
    expect(ActiveStorage::Blob.exists?(too_large.blob.blob.id)).to be false
  end

  it 'drops a file over the field limits on an existing record (TemporaryAttachment.attach_to_record)' do
    user = LimitedUser.create!(name: 'Existing', email: 'existing@example.com')
    temporary('avatar', data: "x" * 11)

    perform_enqueued_jobs { UploadDND::TemporaryAttachment.attach_to_record(session_id, user, { 'avatar' => :avatar }) }

    expect(user.reload.avatar).not_to be_attached
    expect(UploadDND::TemporaryAttachment.for_session(session_id)).to be_empty
  end
end
