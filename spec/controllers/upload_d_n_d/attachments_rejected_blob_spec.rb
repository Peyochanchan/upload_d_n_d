# frozen_string_literal: true

require 'rails_helper'

# Purge des blobs refusés à l'attachement sur un record existant. Chaque chemin
# d'erreur vérifie le statut de la réponse ET le sort du blob. La purge n'est
# possible qu'une fois l'autorisation du record posée : un rejet antérieur
# (cible invalide, record introuvable) ne purge jamais le blob.
RSpec.describe UploadDND::AttachmentsController, type: :controller do
  include ActiveJob::TestHelper

  routes { UploadDND::Engine.routes }

  let(:user) { User.create!(name: 'Test', email: 'test@example.com') }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png')
  end

  def post_blob(target: signed_target_for(user, :avatar))
    perform_enqueued_jobs do
      post :create, params: { signed_blob_id: blob.signed_id, target: target }, format: :json
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

  describe 'rejected uploads are purged (after the record is authorized)' do
    it 'model validation fails (422)' do
      limited = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        def self.name = 'TinyLimitedUser'
        include UploadDND::Uploadable
        uploadable :avatar, max_size: 1
      end
      stub_const('TinyLimitedUser', limited)
      record = TinyLimitedUser.create!(name: 'Test', email: 'test@example.com')

      post_blob(target: signed_target_for(record, :avatar))

      expect(response).to have_http_status(:unprocessable_content)
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

  describe 'rejections before authorization keep the blob' do
    # Cible invalide (ici : attribut non uploadable) refusée à la vérification,
    # avant toute autorisation → aucune purge.
    it 'invalid target (400): the blob is kept' do
      post_blob(target: UploadDND::SignedTarget.generate(User, :internal_file))

      expect(response).to have_http_status(:bad_request)
      expect(blob_exists?).to be true
    end

    # Record signé introuvable (404) : l'autorisation de purge n'est jamais
    # posée (F5) → le blob relève du nettoyage des orphelins.
    it 'record not found (404): the blob is kept, not purged' do
      post_blob(target: UploadDND::SignedTarget.generate(User, :avatar, record_id: 99_999))

      expect(response).to have_http_status(:not_found)
      expect(blob_exists?).to be true
    end
  end

  it 'keeps a blob already attached to another record (rejected, 422)' do
    other = User.create!(name: 'Other', email: 'other@example.com')
    other.avatar.attach(blob)

    post_blob

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

    it 'record policy refuses (403), keeps the blob' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise Pundit::NotAuthorizedError if target.is_a?(User)
      end

      post_blob

      expect(response).to have_http_status(:forbidden)
      expect(blob_exists?).to be true
    end

    it 'record policy raises an unexpected error (500), keeps the blob' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise StandardError, 'policy crashed' if target.is_a?(User)
      end

      post_blob

      expect(response).to have_http_status(:internal_server_error)
      expect(blob_exists?).to be true
    end

    # Fail-closed : pas de policy pour le record → refus (403), blob conservé.
    it 'record has no policy (fail-closed, 403), keeps the blob' do
      controller.singleton_class.define_method(:authorize) do |target, _query|
        raise Pundit::NotDefinedError if target.is_a?(User)
      end

      post_blob

      expect(response).to have_http_status(:forbidden)
      expect(blob_exists?).to be true
    end
  end

  # F7 : find_signed renvoie nil (il ne lève pas) sur signature invalide ;
  # la requête doit être refusée en 401, pas planter en 500.
  it 'invalid blob signature is refused (401), not a 500' do
    bogus = 'A' * 40 # format valide, signature invalide

    post :create, params: { signed_blob_id: bogus, target: signed_target_for(user, :avatar) }, format: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'accepted upload keeps the blob and enqueues no purge' do
    expect {
      post :create, params: { signed_blob_id: blob.signed_id, target: signed_target_for(user, :avatar) }, format: :json
    }.not_to have_enqueued_job(UploadDND::PurgeRejectedBlobJob)

    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar).to be_attached
  end
end
