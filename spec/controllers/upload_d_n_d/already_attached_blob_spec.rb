# frozen_string_literal: true

require 'rails_helper'

# SÉCURITÉ : le signed_id d'un blob figure dans chaque URL de fichier. Un blob
# déjà rattaché (record ou fichier temporaire) ne doit pas pouvoir être
# rattaché une seconde fois par un autre utilisateur.
RSpec.shared_context 'already attached blobs' do
  include ActiveJob::TestHelper

  routes { UploadDND::Engine.routes }

  let(:owner) { User.create!(name: 'Owner', email: 'owner@example.com') }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("private data"), filename: 'x.png', content_type: 'image/png')
  end

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = nil
    end
    allow(controller).to receive(:session).and_return({ id: SecureRandom.uuid })
  end

  after { UploadDND.reset_configuration! }

  def error_message
    JSON.parse(response.body)['error']
  end
end

RSpec.describe UploadDND::TemporaryAttachmentsController, type: :controller do
  include_context 'already attached blobs'

  def post_blob
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'documents' }, format: :json
    end
  end

  it 'refuses a blob attached to a record (422) and leaves it intact' do
    owner.avatar.attach(blob)

    expect { post_blob }.not_to change(UploadDND::TemporaryAttachment, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(error_message).to eq(I18n.t('upload_d_n_d.errors.blob_already_attached'))
    expect(blob.reload.attachments.map(&:record)).to eq([ owner ])
    expect(owner.reload.avatar.download).to eq("private data")
  end

  it 'refuses a blob held by another temporary file (422) and leaves it intact' do
    other = UploadDND::TemporaryAttachment.create!(session_id: 'other', attribute_name: 'documents')
    other.blob.attach(blob)

    expect { post_blob }.not_to change(UploadDND::TemporaryAttachment, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(blob.reload.attachments.count).to eq(1)
    expect(other.reload.blob).to be_attached
  end

  it 'refuses before purging the previous temporary file of a singular attribute' do
    owner.avatar.attach(blob)
    mine = UploadDND::TemporaryAttachment.create!(session_id: controller.session[:id], attribute_name: 'avatar')
    mine.blob.attach(io: StringIO.new("mine"), filename: 'mine.png', content_type: 'image/png')

    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: 'avatar' }, format: :json
    end

    expect(response).to have_http_status(:unprocessable_content)
    expect(UploadDND::TemporaryAttachment.exists?(mine.id)).to be true
  end

  it 'checks authorization first: an unauthorized request gets 403' do
    stub_const('Pundit', Module.new)
    stub_const('Pundit::NotDefinedError', Class.new(StandardError))
    stub_const('Pundit::NotAuthorizedError', Class.new(StandardError))
    UploadDND.configure { |config| config.authorization_adapter = :pundit }
    controller.singleton_class.define_method(:authorize) { |*| raise Pundit::NotAuthorizedError }
    owner.avatar.attach(blob)

    post_blob

    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts a fresh upload' do
    post_blob

    expect(response).to have_http_status(:ok)
    expect(UploadDND::TemporaryAttachment.last.blob.blob).to eq(blob)
  end
end

RSpec.describe UploadDND::AttachmentsController, type: :controller do
  include_context 'already attached blobs'

  let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

  def post_blob(attribute_name: 'avatar')
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, attribute_name: attribute_name, record_gid: user.to_global_id.to_s }, format: :json
    end
  end

  it 'refuses a blob attached to another record (422) and leaves it intact' do
    owner.avatar.attach(blob)

    post_blob

    expect(response).to have_http_status(:unprocessable_content)
    expect(error_message).to eq(I18n.t('upload_d_n_d.errors.blob_already_attached'))
    expect(user.reload.avatar).not_to be_attached
    expect(owner.reload.avatar.download).to eq("private data")
  end

  it 'refuses a blob held by a temporary file (422)' do
    temp = UploadDND::TemporaryAttachment.create!(session_id: 'other', attribute_name: 'documents')
    temp.blob.attach(blob)

    post_blob(attribute_name: 'documents')

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.documents).to be_empty
    expect(temp.reload.blob).to be_attached
  end

  it 'accepts a fresh upload' do
    post_blob

    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar.blob).to eq(blob)
  end
end
