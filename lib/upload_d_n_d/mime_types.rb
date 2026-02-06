# frozen_string_literal: true

module UploadDND
  module MimeTypes
    EXTENSION_TO_MIME = {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      gif: "image/gif",
      webp: "image/webp",
      svg: "image/svg+xml",
      pdf: "application/pdf",
      doc: "application/msword",
      docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      xls: "application/vnd.ms-excel",
      xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ppt: "application/vnd.ms-powerpoint",
      pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      odt: "application/vnd.oasis.opendocument.text",
      txt: "text/plain",
      csv: "text/csv",
      zip: "application/zip"
    }.freeze

    MIME_TO_EXTENSION = EXTENSION_TO_MIME.each_with_object({}) do |(ext, mime), hash|
      hash[mime] ||= ".#{ext}"
    end.freeze

    # Converts an array of symbols (extensions) and/or MIME strings into MIME strings.
    #
    # @param types [Array<Symbol, String>] e.g. [:jpg, :png, "application/pdf"]
    # @return [Array<String>] e.g. ["image/jpeg", "image/png", "application/pdf"]
    def self.resolve(types)
      Array(types).map do |type|
        case type
        when Symbol
          EXTENSION_TO_MIME.fetch(type) { raise ArgumentError, "Unknown extension: #{type.inspect}" }
        else
          type.to_s
        end
      end
    end

    # Converts an array of MIME strings into a comma-separated extensions string
    # suitable for the HTML `accept` attribute.
    #
    # @param mime_types [Array<String>] e.g. ["image/jpeg", "image/png"]
    # @return [String] e.g. ".jpg,.png"
    def self.to_extensions(mime_types)
      Array(mime_types).map { |mime| MIME_TO_EXTENSION[mime] || mime }.join(",")
    end
  end
end
