# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::PurgeOrphanBlobsJob do
  def orphan_blob
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img'), filename: 'x.jpg', content_type: 'image/jpeg', identify: false)
                       .tap { |b| b.update_columns(created_at: 3.days.ago) } # rubocop:disable Rails/SkipsModelValidations
  end

  it 'reports without deleting by default (dry-run)' do
    blob = orphan_blob

    described_class.perform_now

    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
  end

  it 'purges the orphan blobs with apply: true' do
    blob = orphan_blob

    described_class.perform_now(apply: true)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
  end

  it 'never purges a cited blob, even with apply: true' do
    blob = orphan_blob
    path = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    TextPage.create!(body: %(<img src="#{path}">))

    described_class.perform_now(apply: true)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
  end
end
