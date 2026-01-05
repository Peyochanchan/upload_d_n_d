# frozen_string_literal: true

FactoryBot.define do
  factory :temporary_attachment, class: 'UploadDND::TemporaryAttachment' do
    session_id { SecureRandom.uuid }
    attribute_name { 'avatar' }
    user_id { nil }

    after(:create) do |temp_attachment|
      # Crée et attache un blob ActiveStorage au temporary_attachment
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("fake image data"),
        filename: 'test.png',
        content_type: 'image/png'
      )
      temp_attachment.blob.attach(blob)
    end

    trait :with_user do
      user_id { 1 }
    end

    trait :pdf do
      attribute_name { 'document' }
      after(:create) do |temp_attachment|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("fake pdf data"),
          filename: 'test.pdf',
          content_type: 'application/pdf'
        )
        temp_attachment.blob.purge if temp_attachment.blob.attached?
        temp_attachment.blob.attach(blob)
      end
    end

    trait :expired do
      created_at { 8.days.ago }
    end
  end
end
