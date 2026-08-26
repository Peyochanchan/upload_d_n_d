namespace :upload_d_n_d do
  desc "Link gem JS into node_modules for jsbundling compatibility"
  task :link_js do
    gem_spec = Gem.loaded_specs["upload_d_n_d"]
    next unless gem_spec

    gem_path  = gem_spec.gem_dir
    link_path = Rails.root.join("node_modules", "upload_d_n_d")

    unless link_path.exist?
      FileUtils.mkdir_p(link_path.dirname)
      FileUtils.ln_s(gem_path, link_path.to_s)
      puts "upload_d_n_d: linked JS #{link_path} → #{gem_path}"
    end
  end
end

if Rake::Task.task_defined?("javascript:build")
  Rake::Task["javascript:build"].enhance([ "upload_d_n_d:link_js" ])
end
