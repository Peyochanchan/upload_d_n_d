# frozen_string_literal: true

namespace :upload_d_n_d do
  desc "Liste les blobs orphelins (sans rattachement, > min_age, non cités dans un texte). Simulation sauf APPLY=1"
  task purge_orphans: :environment do
    apply = ENV["APPLY"] == "1"
    results = UploadDND::OrphanBlobs.call

    results.each do |result|
      blob = result.blob
      puts "blob ##{blob.id} | #{blob.created_at.to_date} | #{blob.filename} | " \
           "#{ActiveSupport::NumberHelper.number_to_human_size(blob.byte_size)} | service=#{blob.service_name}"
      if result.purgeable?
        blob.purge if apply
        puts "    → #{apply ? "supprimé" : "à supprimer"}"
      else
        puts "    → cité dans #{result.citations.join(", ")} : conservé"
      end
    end

    purgeable = results.select(&:purgeable?)
    size = ActiveSupport::NumberHelper.number_to_human_size(purgeable.sum { |result| result.blob.byte_size })
    puts "#{apply ? "APPLIQUÉ" : "SIMULATION (APPLY=1 pour appliquer)"} : " \
         "#{purgeable.size} blob(s) #{apply ? "supprimé(s)" : "à supprimer"} (#{size}), " \
         "#{results.size - purgeable.size} cité(s) dans un texte et conservé(s)."
  end
end
