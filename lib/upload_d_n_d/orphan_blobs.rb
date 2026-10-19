# frozen_string_literal: true

module UploadDND
  # Blobs sans rattachement qu'on peut supprimer : envois DirectUpload ratés ou
  # abandonnés (refus, coupure réseau, onglet fermé, image retirée d'un éditeur).
  # Le service ne supprime jamais : il LISTE, chaque blob accompagné de ses
  # citations. C'est l'appelant (job, tâche rake) qui décide de purger.
  #
  # Un blob est supprimable seulement si, cumulativement :
  # - aucun ActiveStorage::Attachment (record, variante, Action Text) ;
  # - créé depuis plus de min_age ;
  # - non gardé par un UploadDND::TemporaryAttachment (son blob est rattaché au
  #   temporaire, donc déjà exclu par where.missing(:attachments)) ;
  # - non cité dans un texte de la base (colonnes texte ET JSON) : par la clé du
  #   bucket, par le signed_id (brut et échappé), ou par sgid (fichier inséré
  #   avec l'éditeur dans un HTML stocké hors Action Text). Jamais par le nom.
  #
  # Le scan des citations ne lit que les textes contenant une adresse de
  # stockage ou un sgid (filtre SQL LIKE), une seule fois pour tous les
  # candidats. PostgreSQL requis (CAST AS text + ILIKE).
  class OrphanBlobs
    Result = Data.define(:blob, :citations) do
      def purgeable? = citations.empty?
    end

    # Tables sans texte de contenu, ou dont les adresses ne comptent pas.
    DEFAULT_EXCLUDED_TABLES = %w[
      active_storage_blobs active_storage_attachments active_storage_variant_records
      upload_d_n_d_temporary_attachments
      schema_migrations ar_internal_metadata
    ].freeze

    # Seuls les textes contenant une adresse Active Storage ou un fichier inséré
    # (sgid) sont lus. L'app ajoute l'hôte de son bucket via orphan_scan_patterns
    # pour couvrir les citations par URL directe (image collée).
    DEFAULT_PATTERNS = %w[%active_storage% %sgid%].freeze

    TEXT_TYPES = %i[string text json jsonb].freeze

    def self.call(**) = new(**).call

    def initialize(now: Time.current, min_age: nil)
      @now = now
      @min_age = min_age || UploadDND.configuration.orphan_blob_min_age
    end

    def call
      ensure_postgresql!
      candidates.map { |blob| Result.new(blob: blob, citations: citations_for(blob)) }
    end

    private

    def ensure_postgresql!
      adapter = connection.adapter_name.to_s.downcase
      return if adapter.include?("postgresql") || adapter.include?("postgis")

      raise UploadDND::Error,
            "UploadDND::OrphanBlobs : le scan des citations nécessite PostgreSQL " \
            "(adaptateur courant : #{connection.adapter_name}). " \
            "Sans ce scan, un blob cité dans un texte serait supprimé à tort."
    end

    def candidates
      ActiveStorage::Blob
        .where.missing(:attachments)
        .where(created_at: ...(@now - @min_age))
        .order(:id)
    end

    # Une adresse de fichier contient la clé (bucket) ou le signed_id
    # (Active Storage, stable par défaut).
    def citations_for(blob)
      tokens = [ blob.key, blob.signed_id, CGI.escape(blob.signed_id) ].uniq
      by_url = texts_citing_storage.filter_map do |source, text|
        source if tokens.any? { |token| text.include?(token) }
      end
      (by_url + embedded_blob_sources.fetch(blob.id, [])).uniq
    end

    # { blob_id => ["table.colonne#id", ...] } pour les fichiers insérés (sgid).
    def embedded_blob_sources
      @embedded_blob_sources ||= compute_embedded_blob_sources
    end

    def compute_embedded_blob_sources
      return {} unless defined?(ActionText)

      texts_citing_storage.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(source, text), sources|
        next unless text.include?("sgid")

        ActionText::Content.new(text).attachables.grep(ActiveStorage::Blob).each do |blob|
          sources[blob.id] << source
        end
      end
    end

    # [["table.colonne#id", texte], ...], lus une seule fois.
    def texts_citing_storage
      @texts_citing_storage ||= scanned_columns.flat_map do |table_name, column, has_id|
        table = Arel::Table.new(table_name)
        as_text = Arel::Nodes::NamedFunction.new("CAST", [ table[column].as("text") ])
        query = table.project(has_id ? table[:id] : Arel.sql("NULL"), as_text)
                     .where(patterns.map { |pattern| as_text.matches(pattern) }.reduce(:or))
        connection.select_rows(query.to_sql).map do |id, text|
          [ "#{table_name}.#{column}#{"##{id}" if id}", text.to_s ]
        end
      end
    end

    # Colonnes à scanner : la liste blanche de l'app si elle est renseignée,
    # sinon toutes les colonnes texte/JSON des tables non exclues.
    def scanned_columns
      whitelist = UploadDND.configuration.orphan_scan_columns
      whitelist.present? ? whitelisted_columns(whitelist) : schema_columns
    end

    def whitelisted_columns(entries)
      Array(entries).filter_map do |entry|
        table, column = entry.to_s.split(".", 2)
        next if table.blank? || column.blank?
        next unless connection.data_source_exists?(table)

        [ table, column, has_id_column?(table) ]
      end
    end

    def schema_columns
      (connection.tables - excluded_tables).flat_map do |table|
        columns = connection.columns(table)
        has_id = columns.any? { |column| column.name == "id" }
        columns.select { |column| TEXT_TYPES.include?(column.type) }
               .map { |column| [ table, column.name, has_id ] }
      end
    end

    def has_id_column?(table)
      connection.columns(table).any? { |column| column.name == "id" }
    end

    def excluded_tables
      DEFAULT_EXCLUDED_TABLES + Array(UploadDND.configuration.orphan_scan_excluded_tables).map(&:to_s)
    end

    def patterns
      (DEFAULT_PATTERNS + Array(UploadDND.configuration.orphan_scan_patterns)).uniq
    end

    def connection = ActiveRecord::Base.connection
  end
end
