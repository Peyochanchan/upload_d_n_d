source "https://rubygems.org"

# Specify your gem's dependencies in upload_d_n_d.gemspec.
gemspec

gem "puma"

gem "pg"
gem "sprockets-rails"
gem "view_component", "~> 3.0"

# App dummy : chaîne Hotwire d'une app hôte, pour tester le composant dans un
# navigateur (développement uniquement, hors gemspec)
gem "importmap-rails"
gem "stimulus-rails"
gem "turbo-rails"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

group :development, :test do
  # RSpec for testing
  gem "rspec-rails", "~> 6.0"
  gem "factory_bot_rails", "~> 6.0"
  gem "faker", "~> 3.0"
end

group :test do
  gem "shoulda-matchers", "~> 5.0"
  gem "database_cleaner-active_record", "~> 2.0"
  gem "simplecov", require: false
end

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
