require "upload_d_n_d/js_link"

namespace :upload_d_n_d do
  desc "Copy gem JS into node_modules for jsbundling compatibility"
  task :link_js do
    gem_spec = Gem.loaded_specs["upload_d_n_d"]
    next unless gem_spec

    gem_path = gem_spec.gem_dir
    dest = Rails.root.join("node_modules", "upload_d_n_d")

    case UploadDND::JsLink.sync(source: gem_path, dest: dest)
    when :created then puts "upload_d_n_d: copied JS → #{dest}"
    when :updated then puts "upload_d_n_d: updated JS → #{dest}"
    when :conflict
      warn "upload_d_n_d: #{dest} existe et n'est pas géré par la gem ; " \
           "laissé tel quel (rien supprimé). Retirez-le pour permettre à " \
           "`rake upload_d_n_d:link_js` d'y copier le JS de la gem."
    end
  end
end

if Rake::Task.task_defined?("javascript:build")
  Rake::Task["javascript:build"].enhance([ "upload_d_n_d:link_js" ])
end
