# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'
require 'json'
require 'stringio'

# Couvre le comportement d'affichage de la tâche (le détail de la copie est
# couvert par UploadDND::JsLink).
RSpec.describe 'rake upload_d_n_d:link_js' do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  before do
    @previous_app = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../../lib/tasks/upload_d_n_d_tasks.rake', __dir__)
  end

  after { Rake.application = @previous_app }

  def dest
    File.join(@root, 'node_modules', 'upload_d_n_d')
  end

  # Faux gem_dir minimal (package.json + un fichier d'export).
  def make_source(version:)
    dir = File.join(@root, "gem-#{version}")
    FileUtils.mkdir_p(File.join(dir, 'app/javascript/upload_d_n_d'))
    File.write(File.join(dir, 'package.json'), JSON.generate(
      name: 'upload_d_n_d', version: version,
      exports: { '.' => './app/javascript/upload_d_n_d/index.js' }
    ))
    File.write(File.join(dir, 'app/javascript/upload_d_n_d/index.js'), "// v#{version}\n")
    dir
  end

  # Invoque la tâche avec un gem_dir donné, en capturant stdout/stderr.
  def invoke(gem_dir:)
    allow(Gem).to receive(:loaded_specs)
      .and_return('upload_d_n_d' => instance_double(Gem::Specification, gem_dir: gem_dir))
    allow(Rails).to receive(:root).and_return(Pathname.new(@root))

    out = StringIO.new
    err = StringIO.new
    original_out = $stdout
    original_err = $stderr
    $stdout = out
    $stderr = err
    begin
      Rake::Task['upload_d_n_d:link_js'].reenable
      Rake::Task['upload_d_n_d:link_js'].invoke
    ensure
      $stdout = original_out
      $stderr = original_err
    end
    [ out.string, err.string ]
  end

  it 'affiche un message et copie le JS quand la destination est absente' do
    out, err = invoke(gem_dir: make_source(version: '0.9.4'))

    expect(out).to include('copied JS')
    expect(err).to be_empty
    expect(File.directory?(dest)).to be(true)
    expect(File.file?(File.join(dest, 'package.json'))).to be(true)
  end

  it 'n\'affiche rien quand la copie est déjà à jour' do
    src = make_source(version: '0.9.4')
    invoke(gem_dir: src)

    out, err = invoke(gem_dir: src)

    expect(out).to be_empty
    expect(err).to be_empty
  end

  it 'avertit sans rien supprimer quand un dossier étranger occupe l\'emplacement' do
    FileUtils.mkdir_p(dest)
    File.write(File.join(dest, 'package.json'), JSON.generate(name: 'autre', version: '1.0.0'))

    out, err = invoke(gem_dir: make_source(version: '0.9.4'))

    expect(out).to be_empty
    expect(err).to match(/n'est pas géré par la gem/)
    expect(File.directory?(dest)).to be(true)
    expect(JSON.parse(File.read(File.join(dest, 'package.json')))['name']).to eq('autre')
  end
end
