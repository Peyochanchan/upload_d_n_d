# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::Configuration do
  describe 'default configuration' do
    subject(:config) { described_class.new }

    it 'sets default max_size' do
      expect(config.max_size).to eq(10.megabytes)
    end

    it 'sets default accepted_types' do
      expect(config.accepted_types).to eq('.pdf,.doc,.docx,.jpg,.jpeg,.png,.gif')
    end

    it 'sets default main_color' do
      expect(config.main_color).to eq('#E97451')
    end

    it 'sets default allow_anonymous_uploads' do
      expect(config.allow_anonymous_uploads).to be_falsey
    end

    it 'sets default temporary_files_retention' do
      expect(config.temporary_files_retention).to eq(7)
    end

    it 'sets default rate_limit_enabled' do
      expect(config.rate_limit_enabled).to be_falsey
    end

    it 'sets default rate_limit_max_requests' do
      expect(config.rate_limit_max_requests).to eq(10)
    end

    it 'sets default rate_limit_period' do
      expect(config.rate_limit_period).to eq(60)
    end

    it 'sets default delete_route to :engine' do
      expect(config.delete_route).to eq(:engine)
    end

    it 'sets default on_file_removed' do
      expect(config.on_file_removed).to be_nil
    end
  end

  describe 'custom configuration' do
    before do
      UploadDND.configure do |config|
        config.max_size = 50.megabytes
        config.accepted_types = '.jpg,.png'
        config.main_color = '#FF0000'
        config.temporary_files_retention = 14
      end
    end

    after do
      UploadDND.reset_configuration!
    end

    it 'allows custom max_size' do
      expect(UploadDND.configuration.max_size).to eq(50.megabytes)
    end

    it 'allows custom accepted_types' do
      expect(UploadDND.configuration.accepted_types).to eq('.jpg,.png')
    end

    it 'allows custom main_color' do
      expect(UploadDND.configuration.main_color).to eq('#FF0000')
    end

    it 'allows custom temporary_files_retention' do
      expect(UploadDND.configuration.temporary_files_retention).to eq(14)
    end
  end

  describe 'callbacks' do
    let(:on_upload_success) { ->(blob, user) { "success" } }
    let(:on_upload_error) { ->(error, user) { "error" } }

    before do
      UploadDND.configure do |config|
        config.on_upload_success = on_upload_success
        config.on_upload_error = on_upload_error
      end
    end

    after do
      UploadDND.reset_configuration!
    end

    it 'allows setting on_upload_success callback' do
      expect(UploadDND.configuration.on_upload_success).to eq(on_upload_success)
    end

    it 'allows setting on_upload_error callback' do
      expect(UploadDND.configuration.on_upload_error).to eq(on_upload_error)
    end

    it 'executes on_upload_success callback' do
      blob = double('blob')
      user = double('user')

      result = UploadDND.configuration.on_upload_success.call(blob, user)
      expect(result).to eq("success")
    end
  end

  describe '.reset_configuration!' do
    before do
      UploadDND.configure do |config|
        config.max_size = 100.megabytes
      end
    end

    it 'resets to default configuration' do
      expect(UploadDND.configuration.max_size).to eq(100.megabytes)

      UploadDND.reset_configuration!

      expect(UploadDND.configuration.max_size).to eq(10.megabytes)
    end
  end
end
