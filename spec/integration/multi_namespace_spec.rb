# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multi-namespace support', type: :integration do
  # Créer les tables avant tous les tests
  before(:all) do
    ActiveRecord::Schema.define do
      # Cette spec s'exécute parfois seule pendant le dev; on évite qu'une table
      # manquante (ou incomplète) casse le reste de la suite.
      unless table_exists?(:users)
        create_table :users do |t|
          t.string :email
          t.string :name
          t.timestamps
        end
      end

      add_column :users, :email, :string unless column_exists?(:users, :email)
      add_column :users, :name, :string unless column_exists?(:users, :name)

      create_table :admin_articles, force: true do |t|
        t.string :title
        t.timestamps
      end

      create_table :manager_reports, force: true do |t|
        t.string :title
        t.timestamps
      end
    end

    # Après modification dynamique du schéma, on invalide les caches AR pour éviter
    # les erreurs du type "cached plan must not change result type" (PostgreSQL).
    connection = ActiveRecord::Base.connection
    connection.schema_cache.clear!
    connection.clear_cache!
    User.reset_column_information
    Admin::Article.reset_column_information
    Manager::Report.reset_column_information
  end

  # Supprimer les tables après tous les tests
  after(:all) do
    ActiveRecord::Schema.define do
      drop_table :admin_articles, if_exists: true
      drop_table :manager_reports, if_exists: true
    end

    connection = ActiveRecord::Base.connection
    connection.schema_cache.clear!
    connection.clear_cache!
  end

  describe 'GlobalID avec différents namespaces' do
    context 'avec un modèle sans namespace' do
      let(:user) { User.create!(name: 'Test User') }

      it 'génère un GlobalID valide' do
        gid = user.to_global_id.to_s
        expect(gid).to include('User')
        expect(gid).to include(user.id.to_s)
      end

      it 'peut retrouver le record via GlobalID' do
        gid = user.to_global_id.to_s
        found_record = GlobalID::Locator.locate(gid)

        expect(found_record).to eq(user)
        expect(found_record.class).to eq(User)
      end
    end

    context 'avec un modèle dans namespace Admin' do
      let(:article) { Admin::Article.create!(title: 'Test Article') }

      it 'génère un GlobalID valide avec le namespace' do
        gid = article.to_global_id.to_s
        expect(gid).to include('Admin::Article')
        expect(gid).to include(article.id.to_s)
      end

      it 'peut retrouver le record via GlobalID' do
        gid = article.to_global_id.to_s
        found_record = GlobalID::Locator.locate(gid)

        expect(found_record).to eq(article)
        expect(found_record.class).to eq(Admin::Article)
      end

      it 'le model_name gère correctement le namespace' do
        component = UploadDND::UploadComponent.new(
          attribute_name: :images,
          record: article
        )

        # admin/article devient admin_article (pas de / pour les IDs DOM)
        expect(component.model_name).to eq('admin_article')
      end
    end

    context 'avec un modèle dans namespace Manager' do
      let(:report) { Manager::Report.create!(title: 'Test Report') }

      it 'génère un GlobalID valide avec le namespace' do
        gid = report.to_global_id.to_s
        expect(gid).to include('Manager::Report')
        expect(gid).to include(report.id.to_s)
      end

      it 'peut retrouver le record via GlobalID' do
        gid = report.to_global_id.to_s
        found_record = GlobalID::Locator.locate(gid)

        expect(found_record).to eq(report)
        expect(found_record.class).to eq(Manager::Report)
      end

      it 'le model_name gère correctement le namespace' do
        component = UploadDND::UploadComponent.new(
          attribute_name: :pdf_file,
          record: report
        )

        expect(component.model_name).to eq('manager_report')
      end
    end
  end

  describe 'ViewComponent avec différents namespaces' do
    let(:user) { User.create!(name: 'Test User') }
    let(:article) { Admin::Article.create!(title: 'Test Article') }
    let(:report) { Manager::Report.create!(title: 'Test Report') }

    it 'génère le record_gid pour un modèle sans namespace' do
      component = UploadDND::UploadComponent.new(
        attribute_name: :avatar,
        record: user
      )

      expect(component.record_gid).to be_present
      expect(component.record_gid).to include('User')
    end

    it 'génère le record_gid pour un modèle Admin' do
      component = UploadDND::UploadComponent.new(
        attribute_name: :images,
        record: article
      )

      expect(component.record_gid).to be_present
      expect(component.record_gid).to include('Admin::Article')
    end

    it 'génère le record_gid pour un modèle Manager' do
      component = UploadDND::UploadComponent.new(
        attribute_name: :pdf_file,
        record: report
      )

      expect(component.record_gid).to be_present
      expect(component.record_gid).to include('Manager::Report')
    end
  end

  describe 'Controller avec GlobalID' do
    let(:user) { User.create!(name: 'Test User') }
    let(:article) { Admin::Article.create!(title: 'Test Article') }

    it 'retrouve un User via GlobalID' do
      gid = user.to_global_id.to_s
      found = GlobalID::Locator.locate(gid)

      expect(found).to be_a(User)
      expect(found.id).to eq(user.id)
    end

    it 'retrouve un Admin::Article via GlobalID' do
      gid = article.to_global_id.to_s
      found = GlobalID::Locator.locate(gid)

      expect(found).to be_a(Admin::Article)
      expect(found.id).to eq(article.id)
    end

    it 'lève une exception pour un GlobalID invalide' do
      invalid_gid = 'gid://app/User/999999'

      expect {
        GlobalID::Locator.locate(invalid_gid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
