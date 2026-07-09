# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadableTestController, type: :controller do
  # IMPORTANT: on utilise un RouteSet isolé pour ne pas polluer
  # Rails.application.routes (sinon, specs ordre-dépendantes).
  routes { ActionDispatch::Routing::RouteSet.new }

  before do
    routes.draw do
      get 'index' => 'uploadable_test#index'
      post 'test_attach_files' => 'uploadable_test#test_attach_files'
      get 'test_namespace' => 'uploadable_test#test_namespace'
      get 'test_find_record' => 'uploadable_test#test_find_record'
      post 'attach_file' => 'uploadable_test#attach_file'
      delete 'remove_file' => 'uploadable_test#remove_file'
    end
  end

  describe '#attach_upload_d_n_d_files' do
    let(:user) { User.create!(name: 'Test User', email: 'test@example.com') }
    let(:session_id) { SecureRandom.uuid }

    before do
      allow(controller).to receive(:session).and_return(double(id: session_id))
    end

    context 'with has_one_attached' do
      it 'attaches temporary file to record' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("avatar data"),
          filename: 'avatar.jpg',
          content_type: 'image/jpeg'
        )

        temp = UploadDND::TemporaryAttachment.create!(
          session_id: session_id,
          attribute_name: 'avatar'
        )
        temp.blob.attach(blob)

        expect(user.avatar).not_to be_attached

        post :test_attach_files, params: { id: user.id, attribute_name: 'avatar' }

        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar.filename.to_s).to eq('avatar.jpg')
      end

      it 'destroys temporary attachment after attaching' do
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("avatar data"),
          filename: 'avatar.jpg'
        )

        temp = UploadDND::TemporaryAttachment.create!(
          session_id: session_id,
          attribute_name: 'avatar'
        )
        temp.blob.attach(blob)

        expect {
          post :test_attach_files, params: { id: user.id, attribute_name: 'avatar' }
        }.to change(UploadDND::TemporaryAttachment, :count).by(-1)
      end
    end

    context 'with has_many_attached' do
      it 'attaches multiple temporary files to record' do
        blob1 = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("doc1"),
          filename: 'doc1.pdf'
        )
        blob2 = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("doc2"),
          filename: 'doc2.pdf'
        )

        temp1 = UploadDND::TemporaryAttachment.create!(
          session_id: session_id,
          attribute_name: 'documents'
        )
        temp1.blob.attach(blob1)

        temp2 = UploadDND::TemporaryAttachment.create!(
          session_id: session_id,
          attribute_name: 'documents'
        )
        temp2.blob.attach(blob2)

        expect(user.documents).not_to be_attached

        post :test_attach_files, params: { id: user.id, attribute_name: 'documents' }

        user.reload
        expect(user.documents).to be_attached
        expect(user.documents.count).to eq(2)
      end
    end

    context 'with different session' do
      it 'does not attach files from other sessions' do
        other_session_id = SecureRandom.uuid

        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("data"),
          filename: 'file.pdf'
        )

        temp = UploadDND::TemporaryAttachment.create!(
          session_id: other_session_id,
          attribute_name: 'avatar'
        )
        temp.blob.attach(blob)

        post :test_attach_files, params: { id: user.id, attribute_name: 'avatar' }

        user.reload
        expect(user.avatar).not_to be_attached
      end
    end
  end

  describe '#controller_namespace' do
    it 'returns nil for controllers without namespace' do
      get :test_namespace

      namespace = JSON.parse(response.body)['namespace']
      expect(namespace).to be_nil
    end
  end

  describe '#find_record_for_upload' do
    let!(:user) { User.create!(name: 'Test', email: 'test@example.com') }

    it 'finds record by model name and id' do
      get :test_find_record, params: { model_name: 'user', record_id: user.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(user.id)
    end

    it 'raises error for non-existent record' do
      expect {
        get :test_find_record, params: { model_name: 'user', record_id: 99999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises error for invalid model name' do
      expect {
        get :test_find_record, params: { model_name: 'invalid_model', record_id: 1 }
      }.to raise_error(NameError)
    end
  end

  describe '#authorize_record_for_update' do
    let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

    context 'when Pundit is not defined' do
      it 'does not raise error' do
        hide_const('Pundit') if defined?(Pundit)

        expect {
          controller.send(:authorize_record_for_update, user)
        }.not_to raise_error
      end
    end

    context 'when Pundit is defined' do
      before do
        # Simuler la présence de Pundit
        stub_const('Pundit', Module.new)
        allow(controller).to receive(:authorize)
      end

      it 'calls authorize without namespace for regular controllers' do
        expect(controller).to receive(:authorize).with(user, :update?)

        controller.send(:authorize_record_for_update, user)
      end
    end

    context 'when authorize is a private method (Pundit::Authorization)' do
      it 'still calls authorize instead of silently skipping authorization' do
        # allow/expect définissent une méthode publique, ce qui masquait le
        # bug : Pundit expose authorize en privé, et respond_to?(:authorize)
        # sans include_all renvoyait false -> fail-open.
        calls = []
        controller.singleton_class.class_eval do
          define_method(:authorize) { |record, query| calls << [ record, query ] }
          private :authorize
        end

        controller.send(:authorize_record_for_update, user)

        expect(calls).to eq([ [ user, :update? ] ])
      end
    end
  end

  describe '#attach_file' do
    let(:user) { User.create!(name: 'Test', email: 'test@example.com') }
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("file data"),
        filename: 'test.pdf',
        content_type: 'application/pdf'
      )
    end

    before do
      # Simuler l'instance variable @user
      controller.instance_variable_set(:@user, user)
      allow(controller).to receive(:controller_name).and_return('users')
    end

    context 'with JSON format' do
      it 'attaches file and returns success' do
        post :attach_file, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.avatar).to be_attached
      end

      it 'returns error when save fails' do
        allow_any_instance_of(User).to receive(:save).and_return(false)
        allow_any_instance_of(User).to receive(:errors).and_return(
          double(full_messages: [ 'Email is invalid' ])
        )

        post :attach_file, params: {
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('Email is invalid')
      end
    end

    context 'without instance variable' do
      before do
        controller.instance_variable_set(:@user, nil)
      end

      it 'finds record using params' do
        post :attach_file, params: {
          id: user.id,
          signed_blob_id: blob.signed_id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.avatar).to be_attached
      end
    end
  end

  describe '#remove_file' do
    let(:user) { User.create!(name: 'Test', email: 'test@example.com') }
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("file data"),
        filename: 'test.pdf'
      )
    end

    before do
      user.avatar.attach(blob)
      controller.instance_variable_set(:@user, user)
      allow(controller).to receive(:controller_name).and_return('users')
    end

    context 'with valid attachment' do
      it 'removes file and returns success' do
        attachment = user.avatar.attachment

        delete :remove_file, params: {
          file_id: attachment.id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with wrong record' do
      it 'returns error when attachment belongs to different record' do
        other_user = User.create!(name: 'Other', email: 'other@example.com')
        other_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("data"),
          filename: 'other.pdf'
        )
        other_user.avatar.attach(other_blob)
        other_attachment = other_user.avatar.attachment

        delete :remove_file, params: {
          file_id: other_attachment.id,
          attribute_name: 'avatar'
        }, format: :json

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.blob_not_found'))
      end
    end

    context 'with wrong attribute name' do
      it 'returns error when attribute name does not match' do
        attachment = user.avatar.attachment

        delete :remove_file, params: {
          file_id: attachment.id,
          attribute_name: 'documents'  # Wrong attribute
        }, format: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'error handling' do
    describe 'ActiveStorage::IntegrityError' do
      it 'renders error in JSON format' do
        allow(controller).to receive(:index).and_raise(ActiveStorage::IntegrityError)

        get :index, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.corrupted'))
      end
    end

    describe 'ActiveStorage::UnrepresentableError' do
      it 'renders error in JSON format' do
        allow(controller).to receive(:index).and_raise(ActiveStorage::UnrepresentableError)

        get :index, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to eq(I18n.t('upload_d_n_d.errors.unrepresentable'))
      end
    end
  end
end

RSpec.describe Admin::ProjectsController, type: :controller do
  routes { ActionDispatch::Routing::RouteSet.new }

  before do
    routes.draw do
      get 'test_namespace' => 'admin/projects#test_namespace'
    end
  end

  describe '#controller_namespace' do
    it 'returns namespace for namespaced controllers' do
      get :test_namespace

      namespace = JSON.parse(response.body)['namespace']
      expect(namespace).to eq('Admin')
    end
  end

  describe '#authorize_record_for_update' do
    let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

    before do
      stub_const('Pundit', Module.new)
      allow(controller).to receive(:authorize)
    end

    it 'calls authorize with namespace for namespaced controllers' do
      expect(controller).to receive(:authorize).with([ :admin, user ], :update?)

      controller.send(:authorize_record_for_update, user)
    end
  end
end

RSpec.describe Admin::Nested::ProjectsController, type: :controller do
  routes { ActionDispatch::Routing::RouteSet.new }

  before do
    routes.draw do
      get 'test_namespace' => 'admin/nested/projects#test_namespace'
    end
  end

  describe '#controller_namespace' do
    it 'returns full namespace for deeply nested controllers' do
      get :test_namespace

      namespace = JSON.parse(response.body)['namespace']
      expect(namespace).to eq('Admin::Nested')
    end
  end

  describe '#authorize_record_for_update' do
    let(:user) { User.create!(name: 'Test', email: 'test@example.com') }

    before do
      stub_const('Pundit', Module.new)
      allow(controller).to receive(:authorize)
    end

    it 'calls authorize with all namespace parts' do
      expect(controller).to receive(:authorize).with([ :admin, :nested, user ], :update?)

      controller.send(:authorize_record_for_update, user)
    end
  end
end
