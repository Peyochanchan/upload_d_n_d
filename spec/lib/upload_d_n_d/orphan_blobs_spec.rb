# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::OrphanBlobs do
  include ActiveJob::TestHelper

  def blob(created_at: 3.days.ago, filename: 'x.jpg')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img'), filename: filename, content_type: 'image/jpeg', identify: false)
                       .tap { |b| b.update_columns(created_at: created_at) } # rubocop:disable Rails/SkipsModelValidations
  end

  def blob_path(a_blob)
    Rails.application.routes.url_helpers.rails_blob_path(a_blob, only_path: true)
  end

  let(:results) { described_class.call }

  after { UploadDND.reset_configuration! }

  it 'lists an unattached blob older than min_age' do
    orphan = blob
    expect(results.sole).to have_attributes(blob: orphan, purgeable?: true)
  end

  it 'ignores a recent blob (upload maybe in progress)' do
    blob(created_at: 1.day.ago)
    expect(results).to be_empty
  end

  it 'honours a custom min_age' do
    blob(created_at: 1.day.ago)
    expect(described_class.call(min_age: 12.hours)).not_to be_empty
  end

  it 'ignores an attached blob' do
    User.create!(name: 'U', email: 'u@example.com').avatar.attach(blob)
    expect(results).to be_empty
  end

  it 'ignores a blob held by a temporary attachment (form in progress)' do
    temp = UploadDND::TemporaryAttachment.create!(session_id: 's', attribute_name: 'avatar')
    temp.blob.attach(blob)
    expect(results).to be_empty
  end

  it 'keeps a blob whose Active Storage address is cited in text' do
    orphan = blob
    page = TextPage.create!(body: %(<img src="#{blob_path(orphan)}">))

    expect(results.sole).to have_attributes(purgeable?: false, citations: [ "text_pages.body##{page.id}" ])
  end

  it 'keeps a blob cited in a JSON column' do
    orphan = blob
    page = TextPage.create!(payload: { 'fr' => %(<img src="#{blob_path(orphan)}">) })

    expect(results.sole).to have_attributes(purgeable?: false)
    expect(results.sole.citations.sole).to start_with("text_pages.payload##{page.id}")
  end

  it 'keeps a blob cited by its direct bucket key when the host pattern is configured' do
    UploadDND.configuration.orphan_scan_patterns = [ '%cdn.example%' ]
    orphan = blob
    TextPage.create!(body: "https://cdn.example.test/#{orphan.key}")

    expect(results.sole.purgeable?).to be(false)
  end

  it "keeps a blob embedded with the editor in HTML stored outside Action Text (sgid)" do
    orphan = blob
    html = ActionText::Content.new('').append_attachables([ orphan ]).to_html
    page = TextPage.create!(body: html)

    expect(results.sole.citations).to eq([ "text_pages.body##{page.id}" ])
  end

  # Le nom n'est jamais utilisé : seul le jumeau rattaché, cité par son adresse,
  # est conservé ; l'orphelin homonyme est purgeable.
  it 'does not keep a mere namesake' do
    orphan = blob(filename: 'affiche.jpg')
    twin = blob(filename: 'affiche.jpg')
    User.create!(name: 'U', email: 'u@example.com').avatar.attach(twin)
    TextPage.create!(body: %(<img src="#{blob_path(twin)}">))

    expect(results.sole).to have_attributes(blob: orphan, purgeable?: true)
  end

  it 'limits the scan to the whitelisted columns' do
    orphan = blob
    # Citation dans une colonne NON listée : hors périmètre, donc non vue.
    TextPage.create!(body: %(<img src="#{blob_path(orphan)}">))
    UploadDND.configuration.orphan_scan_columns = [ 'text_pages.payload' ]

    expect(results.sole.purgeable?).to be(true)
  end

  it 'raises a clear error on a non-PostgreSQL connection' do
    fake = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: 'SQLite')
    allow(ActiveRecord::Base).to receive(:connection).and_return(fake)

    expect { described_class.call }.to raise_error(UploadDND::Error, /PostgreSQL/)
  end
end
