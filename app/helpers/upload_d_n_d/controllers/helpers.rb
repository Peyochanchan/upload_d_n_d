# lib/upload_d_n_d/controllers/helpers.rb
module UploadDND
  module Controllers
    module Helpers
      extend ActiveSupport::Concern

      def attach_upload_d_n_d_files(record, attribute_name)
        # On cherche les fichiers temporaires liés à cette session
        temps = UploadDND::TemporaryAttachment.where(
          session_id: session.id.to_s,
          attribute_name: attribute_name
        )

        temps.each do |temp|
          record.send(attribute_name).attach(temp.blob)
          temp.destroy # On nettoie après attachement
        end
      end
    end
  end
end
