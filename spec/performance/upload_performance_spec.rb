# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Upload Performance',  type: :controller do
  controller(UploadDND::TemporaryAttachmentsController) {}

  routes { UploadDND::Engine.routes }

  let(:session_id) { SecureRandom.uuid }

  before do
    UploadDND.configure do |config|
      config.require_authentication = false
      config.authorization_adapter = nil
    end

    # Mock session
    allow(controller).to receive(:session).and_return({ id: session_id })
  end

  after do
    UploadDND.reset_configuration!
  end

  def create_blob(filename: 'test.png')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image data"),
      filename: filename,
      content_type: 'image/png'
    )
  end

  describe 'concurrent uploads' do
    it 'handles multiple concurrent uploads efficiently' do
      blobs = 10.times.map { |i| create_blob(filename: "test#{i}.png") }

      start_time = Time.current

      # Note: Les threads ne fonctionnent pas bien avec RSpec controller tests
      # On teste la performance séquentielle à la place
      blobs.each do |blob|
        post :create,
             params: {
               signed_blob_id: blob.signed_id,
               attribute_name: 'documents'
             },
             format: :json
      end

      duration = Time.current - start_time

      # Devrait gérer 10 uploads séquentiels en moins de 3 secondes
      expect(duration).to be < 3.seconds
      expect(UploadDND::TemporaryAttachment.count).to eq(10)
    end
  end

  describe 'N+1 query prevention' do
    it 'does not generate N+1 queries when listing temp files' do
      # Créer 5 fichiers temporaires
      5.times do |i|
        blob = create_blob(filename: "test#{i}.png")
        post :create,
             params: {
               signed_blob_id: blob.signed_id,
               attribute_name: 'documents'
             },
             format: :json
      end

      # Compter les requêtes lors du rendu de la liste
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
        queries << payload[:sql] unless payload[:sql].include?('SCHEMA')
      end

      # Récupérer les fichiers pour un attribut (avec eager loading)
      files = UploadDND::TemporaryAttachment
                .for_session(session_id)
                .for_attribute('documents')
                .with_blobs

      # Forcer le chargement
      files.map(&:filename)

      ActiveSupport::Notifications.unsubscribe(subscriber)

      # OPTIMISÉ : Avec includes(blob_attachment: :blob), on a ~3 requêtes au lieu de 11
      # 1 requête temp_attachments + 1 requête active_storage_attachments + 1 requête blobs = 3 requêtes
      expect(queries.size).to be <= 5, "Expected <= 5 queries, got #{queries.size}. Queries: #{queries.join("\n")}"
    end
  end

  describe 'singular attribute cleanup performance' do
    it 'efficiently purges existing temp files for has_one_attached attributes' do
      # Créer 100 anciens fichiers pour l'attribut "avatar" (singulier)
      100.times do |i|
        UploadDND::TemporaryAttachment.create!(
          session_id: session_id,
          attribute_name: 'avatar'
        ).tap do |ta|
          blob = create_blob(filename: "old_avatar#{i}.png")
          ta.blob.attach(blob)
        end
      end

      expect(UploadDND::TemporaryAttachment.count).to eq(100)

      # Mesurer le temps de destruction lors d'un nouvel upload
      start_time = Time.current

      new_blob = create_blob(filename: 'new_avatar.png')
      post :create,
           params: {
             signed_blob_id: new_blob.signed_id,
             attribute_name: 'avatar'
           },
           format: :json

      duration = Time.current - start_time

      # Devrait purger 100 fichiers et en créer 1 en moins de 5 secondes
      expect(duration).to be < 5.seconds

      # Ne devrait rester qu'un seul fichier avatar
      expect(UploadDND::TemporaryAttachment.for_attribute('avatar').count).to eq(1)
      expect(UploadDND::TemporaryAttachment.count).to eq(1)
    end
  end

  describe 'database index effectiveness' do
    it 'uses composite index for session_id + attribute_name queries' do
      # Créer des données de test
      10.times do |i|
        UploadDND::TemporaryAttachment.create!(
          session_id: "session_#{i}",
          attribute_name: "attr_#{i % 3}"
        )
      end

      # Vérifier que la requête utilise l'index composite
      # Note: Ceci est un test approximatif, un vrai test nécessiterait EXPLAIN
      start_time = Time.current

      100.times do
        UploadDND::TemporaryAttachment
          .for_session('session_1')
          .for_attribute('attr_1')
          .to_a
      end

      duration = Time.current - start_time

      # Si l'index est utilisé, 100 requêtes devraient être très rapides
      expect(duration).to be < 0.5.seconds
    end
  end

  describe 'memory efficiency' do
    it 'uses find_each for bulk operations to avoid loading all records' do
      # Créer beaucoup de fichiers expirés
      50.times do |i|
        UploadDND::TemporaryAttachment.create!(
          session_id: "session_#{i}",
          attribute_name: 'documents',
          created_at: 10.days.ago
        )
      end

      # Mesurer la mémoire avant
      GC.start
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i

      # Nettoyer les fichiers expirés
      UploadDND::TemporaryAttachment.cleanup_expired!

      # Mesurer la mémoire après
      GC.start
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i

      # La différence de mémoire ne devrait pas exploser
      # (find_each charge par batch de 1000, donc mémoire stable)
      memory_increase = memory_after - memory_before

      # Tolérance de 50MB pour le test
      expect(memory_increase).to be < 50_000
    end
  end
end
