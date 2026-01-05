# frozen_string_literal: true

# Helper methods for ActiveStorage testing
module ActiveStorageTestHelpers
  def create_file_blob(filename: 'test.png', content_type: 'image/png', content: 'fake data')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )
  end

  def attach_file_to(record, attribute, filename: 'test.png', content_type: 'image/png')
    blob = create_file_blob(filename: filename, content_type: content_type)
    record.send(attribute).attach(blob)
    record
  end
end

RSpec.configure do |config|
  config.include ActiveStorageTestHelpers
end
