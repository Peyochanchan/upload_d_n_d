# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::PurgeRejectedBlobJob, type: :job do
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("data"), filename: 'x.png', content_type: 'image/png')
  end

  it 'purges a blob that is still unattached' do
    described_class.perform_now(blob.id)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
  end

  # Le blob a pu être rattaché entre le refus et l'exécution du job (nouvel
  # essai réussi avec le même signed_id) : la purge doit être annulée.
  it 'keeps a blob attached to a record between the rejection and the job' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    user.avatar.attach(blob)

    described_class.perform_now(blob.id)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    expect(user.reload.avatar).to be_attached
    expect(user.avatar.download).to eq("data")
  end

  it 'keeps a blob held by a TemporaryAttachment between the rejection and the job' do
    temp = UploadDND::TemporaryAttachment.create!(session_id: 'sid', attribute_name: 'avatar')
    temp.blob.attach(blob)

    described_class.perform_now(blob.id)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
  end

  # L'âge est contrôlé au refus : le délai de la file ne bloque pas la purge.
  it 'purges an unattached blob even if the queue delayed it past the window' do
    blob.update_column(:created_at, 2.days.ago)

    described_class.perform_now(blob.id)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
  end

  it 'does nothing when the blob no longer exists' do
    id = blob.id
    blob.purge

    expect { described_class.perform_now(id) }.not_to raise_error
  end
end
