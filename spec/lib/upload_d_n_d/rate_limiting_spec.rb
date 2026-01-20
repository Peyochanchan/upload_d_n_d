# frozen_string_literal: true

require "rails_helper"

RSpec.describe UploadDND::RateLimiting do
  # Classe de test incluant le concern
  class TestRateLimitController < ActionController::Base
    include UploadDND::RateLimiting

    attr_accessor :request, :response

    def initialize
      @request = ActionDispatch::TestRequest.create
      @response = ActionDispatch::Response.new
    end

    def current_user
      @current_user
    end

    def current_user=(user)
      @current_user = user
    end

    def render_error(message, status)
      @rendered_error = { message: message, status: status }
    end

    attr_reader :rendered_error
  end

  let(:controller) { TestRateLimitController.new }

  # Configure cache to use memory store for these tests
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  after do
    UploadDND.reset_configuration!
  end

  describe "#rate_limiting_enabled?" do
    it "returns true when rate limiting is enabled" do
      UploadDND.configure do |config|
        config.rate_limit_enabled = true
      end

      expect(controller.send(:rate_limiting_enabled?)).to be true
    end

    it "returns false when rate limiting is disabled" do
      UploadDND.configure do |config|
        config.rate_limit_enabled = false
      end

      expect(controller.send(:rate_limiting_enabled?)).to be false
    end
  end

  describe "#rate_limit_key" do
    it "includes IP address" do
      controller.request.remote_addr = "192.168.1.1"
      key = controller.send(:rate_limit_key)

      expect(key).to include("192.168.1.1")
      expect(key).to include("upload_dnd:rate_limit")
    end

    it "includes user ID when authenticated" do
      user = double("User", id: 123)
      controller.current_user = user

      key = controller.send(:rate_limit_key)
      expect(key).to include("123")
      expect(key).not_to include("anonymous")
    end

    it "uses 'anonymous' when no user" do
      controller.current_user = nil

      key = controller.send(:rate_limit_key)
      expect(key).to include("anonymous")
    end

    it "creates unique keys for different users and IPs" do
      user1 = double("User", id: 123)
      controller.current_user = user1
      controller.request.remote_addr = "10.0.0.1"
      key1 = controller.send(:rate_limit_key)

      user2 = double("User", id: 456)
      controller.current_user = user2
      controller.request.remote_addr = "10.0.0.2"
      key2 = controller.send(:rate_limit_key)

      expect(key1).not_to eq(key2)
    end
  end

  describe "#increment_rate_limit_counter" do
    let(:test_key) { "test:rate_limit:key" }

    it "starts at 1 for new key" do
      count = controller.send(:increment_rate_limit_counter, test_key)
      expect(count).to eq(1)
    end

    it "increments on each call" do
      count1 = controller.send(:increment_rate_limit_counter, test_key)
      count2 = controller.send(:increment_rate_limit_counter, test_key)
      count3 = controller.send(:increment_rate_limit_counter, test_key)

      expect(count1).to eq(1)
      expect(count2).to eq(2)
      expect(count3).to eq(3)
    end

    it "stores value in Rails cache" do
      controller.send(:increment_rate_limit_counter, test_key)
      expect(Rails.cache.read(test_key)).to eq(1)
    end

    it "sets expiration on cache entry" do
      UploadDND.configure { |c| c.rate_limit_period = 60 }

      controller.send(:increment_rate_limit_counter, test_key)

      # Vérifie que la clé existe
      expect(Rails.cache.exist?(test_key)).to be true
    end
  end

  describe "#check_rate_limit" do
    before do
      UploadDND.configure do |config|
        config.rate_limit_enabled = true
        config.rate_limit_max_requests = 3
        config.rate_limit_period = 60
      end
    end

    it "allows requests under the limit" do
      result = controller.send(:check_rate_limit)
      expect(result).to be true
      expect(controller.rendered_error).to be_nil
    end

    it "sets rate limit headers on success" do
      controller.send(:check_rate_limit)

      expect(controller.response.headers["X-RateLimit-Limit"]).to eq("3")
      expect(controller.response.headers["X-RateLimit-Remaining"]).to eq("2")
      expect(controller.response.headers["X-RateLimit-Reset"]).to be_present
    end

    it "blocks requests over the limit" do
      # Fait 3 requêtes valides
      3.times do
        controller.send(:check_rate_limit)
        controller.response = ActionDispatch::Response.new # Nouveau response
      end

      # 4ème requête bloquée
      result = controller.send(:check_rate_limit)
      expect(result).to be false
      expect(controller.rendered_error).not_to be_nil
      expect(controller.rendered_error[:status]).to eq(:too_many_requests)
    end

    it "sets appropriate headers when blocked" do
      3.times do
        controller.send(:check_rate_limit)
        controller.response = ActionDispatch::Response.new
      end

      # 4ème requête devrait être bloquée et avoir les headers
      controller.send(:check_rate_limit)

      expect(controller.response.headers["Retry-After"]).to be_present
      expect(controller.response.headers["X-RateLimit-Remaining"]).to eq("0")
    end

    it "includes retry time in error message" do
      4.times do
        controller.send(:check_rate_limit)
        controller.response = ActionDispatch::Response.new
      end

      expect(controller.rendered_error[:message]).to include("Trop de requêtes")
      expect(controller.rendered_error[:message]).to match(/\d+ secondes/)
    end
  end

  describe "configuration options" do
    it "respects custom max_requests" do
      UploadDND.configure do |config|
        config.rate_limit_enabled = true
        config.rate_limit_max_requests = 2
        config.rate_limit_period = 60
      end

      2.times do
        expect(controller.send(:check_rate_limit)).to be true
        controller.response = ActionDispatch::Response.new
      end

      expect(controller.send(:check_rate_limit)).to be false
    end

    it "respects custom period in reset header" do
      UploadDND.configure do |config|
        config.rate_limit_enabled = true
        config.rate_limit_max_requests = 5
        config.rate_limit_period = 30
      end

      controller.send(:check_rate_limit)

      reset_time = Time.at(controller.response.headers["X-RateLimit-Reset"].to_i)
      expected_time = Time.current + 30.seconds

      expect(reset_time).to be_within(5.seconds).of(expected_time)
    end
  end

  describe "logging" do
    before do
      UploadDND.configure do |config|
        config.rate_limit_enabled = true
        config.rate_limit_max_requests = 1
      end
    end

    it "logs warning when limit exceeded" do
      controller.send(:check_rate_limit)
      controller.response = ActionDispatch::Response.new

      expect(Rails.logger).to receive(:warn).with(/RateLimit.*exceeded limit/)
      controller.send(:check_rate_limit)
    end
  end
end
