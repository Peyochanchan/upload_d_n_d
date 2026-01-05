# frozen_string_literal: true

module UploadDND
  module Generators
    module MimeTypeHelper
      # Mapping des extensions vers MIME types
      EXTENSION_TO_MIME = {
        # Images
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        'bmp' => 'image/bmp',
        'ico' => 'image/x-icon',
        'tiff' => 'image/tiff',
        'tif' => 'image/tiff',

        # Documents
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'odt' => 'application/vnd.oasis.opendocument.text',
        'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
        'odp' => 'application/vnd.oasis.opendocument.presentation',

        # Texte
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'html' => 'text/html',
        'htm' => 'text/html',
        'xml' => 'text/xml',
        'json' => 'application/json',
        'md' => 'text/markdown',

        # Archives
        'zip' => 'application/zip',
        'rar' => 'application/x-rar-compressed',
        '7z' => 'application/x-7z-compressed',
        'tar' => 'application/x-tar',
        'gz' => 'application/gzip',

        # Audio
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        'flac' => 'audio/flac',
        'm4a' => 'audio/mp4',

        # Vidéo
        'mp4' => 'video/mp4',
        'avi' => 'video/x-msvideo',
        'mov' => 'video/quicktime',
        'wmv' => 'video/x-ms-wmv',
        'flv' => 'video/x-flv',
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska'
      }.freeze

      # Convertit une liste d'extensions ou de MIME types en MIME types
      # @param types [Array<String>] Liste d'extensions (ex: ['jpg', 'png']) ou MIME types
      # @return [Array<String>] Liste de MIME types
      def convert_to_mime_types(types)
        types.map do |type|
          type = type.to_s.strip.downcase

          # Si ça commence par un point, on l'enlève
          type = type.delete_prefix('.')

          # Si c'est déjà un MIME type (contient un /), on le garde tel quel
          if type.include?('/')
            type
          # Sinon, on cherche dans notre mapping
          elsif EXTENSION_TO_MIME.key?(type)
            EXTENSION_TO_MIME[type]
          else
            # Si on ne trouve pas, on affiche un warning et on garde tel quel
            say "  ⚠️  Extension inconnue '#{type}', utilisée telle quelle", :yellow
            type
          end
        end.uniq
      end

      # Retourne une liste lisible des extensions supportées
      def supported_extensions
        EXTENSION_TO_MIME.keys.sort
      end

      # Retourne des exemples d'extensions par catégorie
      def extension_examples
        {
          'Images' => %w[jpg png gif webp svg],
          'Documents' => %w[pdf doc docx xls xlsx ppt pptx],
          'Archives' => %w[zip rar 7z tar gz],
          'Audio' => %w[mp3 wav ogg flac],
          'Vidéo' => %w[mp4 avi mov webm]
        }
      end
    end
  end
end
