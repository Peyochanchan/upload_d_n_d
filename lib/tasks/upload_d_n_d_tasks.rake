require "upload_d_n_d/js_link"

namespace :upload_d_n_d do
  desc "Link gem JS into node_modules for jsbundling compatibility"
  task :link_js do
    gem_spec = Gem.loaded_specs["upload_d_n_d"]
    next unless gem_spec

    gem_path  = gem_spec.gem_dir
    link_path = Rails.root.join("node_modules", "upload_d_n_d")

    case UploadDND::JsLink.reconcile(link_path: link_path, target: gem_path)
    when :created then puts "upload_d_n_d: linked JS #{link_path} → #{gem_path}"
    when :updated then puts "upload_d_n_d: relinked JS #{link_path} → #{gem_path}"
    when :conflict
      warn "upload_d_n_d: #{link_path} existe et n'est pas un lien géré par la gem ; " \
           "laissé tel quel (rien supprimé). Retirez-le pour permettre à " \
           "`rake upload_d_n_d:link_js` de créer le lien vers #{gem_path}."
    end
  end
end

if Rake::Task.task_defined?("javascript:build")
  Rake::Task["javascript:build"].enhance([ "upload_d_n_d:link_js" ])
end
