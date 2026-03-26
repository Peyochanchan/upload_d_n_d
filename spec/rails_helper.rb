# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../test/dummy/config/environment', __dir__)

abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'factory_bot_rails'
require 'database_cleaner/active_record'
require 'view_component/test_helpers'

# Turbo (turbo-rails) enregistre normalement ce MIME type. Comme ces specs
# utilisent `respond_to { |format| format.turbo_stream ... }`, on l'enregistre
# en test pour éviter un crash même quand la requête est en JSON.
if defined?(Mime::Type) && Mime::Type.lookup_by_extension(:turbo_stream).nil?
  Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream
end

# Load support files
Dir[File.expand_path('../support/**/*.rb', __FILE__)].sort.each { |f| require f }

# Load factories
FactoryBot.definition_file_paths = [ File.expand_path('../factories', __FILE__) ]
FactoryBot.find_definitions

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods

  # ViewComponent test helpers
  config.include ViewComponent::TestHelpers, type: :component

  # Database Cleaner configuration
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
