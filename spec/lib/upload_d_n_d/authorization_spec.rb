# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadDND::Authorization do
  let(:record) { Object.new }
  let(:controller) { Object.new }

  after { UploadDND.reset_configuration! }

  describe '.adapter' do
    it 'resolves the declared adapters' do
      expect(described_class.adapter(:pundit)).to eq(described_class::PunditAdapter)
      expect(described_class.adapter('cancancan')).to eq(described_class::CanCanCanAdapter)
      expect(described_class.adapter(:none)).to eq(described_class::NoAuthorization)
    end

    it 'falls back to Unconfigured for nil or an unknown value (fail-closed)' do
      expect(described_class.adapter(nil)).to eq(described_class::Unconfigured)
      expect(described_class.adapter(:custom)).to eq(described_class::Unconfigured)
      expect(described_class.adapter(42)).to eq(described_class::Unconfigured)
    end
  end

  describe 'adapter detection' do
    it 'detects nothing without an authorization library (test bundle)' do
      expect(UploadDND::Configuration.new.authorization_adapter).to be_nil
    end

    it 'detects Pundit' do
      stub_const('Pundit', Module.new)

      expect(UploadDND::Configuration.new.authorization_adapter).to eq(:pundit)
    end

    it 'detects CanCanCan' do
      stub_const('CanCan::Ability', Module.new)

      expect(UploadDND::Configuration.new.authorization_adapter).to eq(:cancancan)
    end
  end

  describe 'Unconfigured' do
    it 'refuses and logs' do
      UploadDND.configuration.authorization_adapter = nil
      expect(Rails.logger).to receive(:warn).with(/no authorization adapter configured/)

      expect {
        described_class.authorize!(controller, :upload_d_n_d_attachment, :create)
      }.to raise_error(described_class::Denied)
    end
  end

  describe 'NoAuthorization' do
    it 'lets everything through' do
      UploadDND.configuration.authorization_adapter = :none

      expect(described_class.authorize!(controller, record, :update)).to be_nil
    end
  end

  describe 'PunditAdapter' do
    before { stub_pundit! }

    def controller_with(&block)
      Class.new do
        define_method(:authorize, &block)
        private :authorize
      end.new
    end

    it 'calls authorize with the Pundit query' do
      calls = []
      ctrl = controller_with { |subject, query| calls << [ subject, query ] }

      described_class.authorize!(ctrl, record, :update)

      expect(calls).to eq([ [ record, :update? ] ])
    end

    it 'translates a refusal into Denied, keeping the native error as cause' do
      ctrl = controller_with { |*| raise Pundit::NotAuthorizedError }

      expect {
        described_class.authorize!(ctrl, record, :update)
      }.to raise_error(described_class::Denied) { |e| expect(e.cause).to be_a(Pundit::NotAuthorizedError) }
    end

    it 'translates a missing policy into RuleMissing' do
      ctrl = controller_with { |*| raise Pundit::NotDefinedError }

      expect {
        described_class.authorize!(ctrl, record, :update)
      }.to raise_error(described_class::RuleMissing)
    end

    it 'tries the namespaced policy first, then the top-level one' do
      calls = []
      ctrl = controller_with do |subject, query|
        calls << [ subject, query ]
        raise Pundit::NotDefinedError if subject.is_a?(Array)
      end

      described_class.authorize!(ctrl, record, :update, namespace: [ :admin ])

      expect(calls).to eq([ [ [ :admin, record ], :update? ], [ record, :update? ] ])
    end

    it 'does not fall back when the namespaced policy refuses' do
      ctrl = controller_with { |subject, _| raise Pundit::NotAuthorizedError if subject.is_a?(Array) }

      expect {
        described_class.authorize!(ctrl, record, :update, namespace: [ :admin ])
      }.to raise_error(described_class::Denied)
    end

    it 'raises ConfigurationError when the controller has no authorize' do
      expect {
        described_class.authorize!(controller, record, :update)
      }.to raise_error(described_class::ConfigurationError)
    end

    it 'raises ConfigurationError when Pundit is not loaded' do
      hide_const('Pundit')
      ctrl = controller_with { |*| true }

      expect {
        described_class.authorize!(ctrl, record, :update)
      }.to raise_error(described_class::ConfigurationError)
    end
  end

  describe 'CanCanCanAdapter' do
    before do
      stub_const('CanCan::AccessDenied', Class.new(StandardError))
      UploadDND.configuration.authorization_adapter = :cancancan
    end

    def controller_with(&block)
      Class.new do
        define_method(:authorize!, &block)
        private :authorize!
      end.new
    end

    it 'calls authorize! with the action and the subject' do
      calls = []
      ctrl = controller_with { |action, subject| calls << [ action, subject ] }

      described_class.authorize!(ctrl, :upload_d_n_d_attachment, :create, namespace: [ :admin ])

      expect(calls).to eq([ [ :create, :upload_d_n_d_attachment ] ])
    end

    it 'translates a refusal into Denied' do
      ctrl = controller_with { |*| raise CanCan::AccessDenied }

      expect {
        described_class.authorize!(ctrl, record, :update)
      }.to raise_error(described_class::Denied) { |e| expect(e.cause).to be_a(CanCan::AccessDenied) }
    end

    it 'raises ConfigurationError when the controller has no authorize!' do
      expect {
        described_class.authorize!(controller, record, :update)
      }.to raise_error(described_class::ConfigurationError)
    end
  end

  describe '.report' do
    let(:logger) { instance_double(Logger, warn: nil) }

    it 'warns when authorization is disabled (:none)' do
      UploadDND.configuration.authorization_adapter = :none

      described_class.report(logger)

      expect(logger).to have_received(:warn).with(/authorization disabled/)
    end

    it 'warns that everything is refused without a usable adapter' do
      UploadDND.configuration.authorization_adapter = nil

      described_class.report(logger)

      expect(logger).to have_received(:warn).with(/all uploads and deletions are refused/)
    end

    it 'stays silent with a library adapter' do
      UploadDND.configuration.authorization_adapter = :pundit

      described_class.report(logger)

      expect(logger).not_to have_received(:warn)
    end
  end
end
