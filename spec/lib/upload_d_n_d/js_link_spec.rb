# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'json'
require 'upload_d_n_d/js_link'

RSpec.describe UploadDND::JsLink do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  # node_modules/upload_d_n_d dans une fausse racine d'app.
  def dest
    File.join(@root, 'node_modules', 'upload_d_n_d')
  end

  # Fabrique un faux dossier de gem (comme gem_dir) : package.json + les
  # fichiers de ses exports.
  def make_source(version:)
    dir = File.join(@root, "gem-#{version}")
    FileUtils.mkdir_p(File.join(dir, 'app/javascript/upload_d_n_d/controllers'))
    FileUtils.mkdir_p(File.join(dir, 'app/assets/stylesheets/upload_d_n_d'))
    File.write(File.join(dir, 'package.json'), JSON.generate(
      name: 'upload_d_n_d', version: version, type: 'module',
      exports: {
        '.' => './app/javascript/upload_d_n_d/index.js',
        './controllers/*' => './app/javascript/upload_d_n_d/controllers/*.js',
        './styles' => { 'style' => './app/assets/stylesheets/upload_d_n_d/application.css' }
      }
    ))
    File.write(File.join(dir, 'app/javascript/upload_d_n_d/index.js'), "// index v#{version}\n")
    File.write(File.join(dir, 'app/javascript/upload_d_n_d/controllers/uploads_controller.js'), "// uploads\n")
    File.write(File.join(dir, 'app/assets/stylesheets/upload_d_n_d/application.css'), "/* css */\n")
    dir
  end

  def dest_version
    JSON.parse(File.read(File.join(dest, 'package.json')))['version']
  end

  it 'copie package.json et les fichiers des exports quand la destination est absente' do
    expect(described_class.sync(source: make_source(version: '0.9.4'), dest: dest)).to eq(:created)

    expect(File.symlink?(dest)).to be(false)
    expect(File.file?(File.join(dest, 'package.json'))).to be(true)
    expect(File.file?(File.join(dest, 'app/javascript/upload_d_n_d/index.js'))).to be(true)
    expect(File.file?(File.join(dest, 'app/javascript/upload_d_n_d/controllers/uploads_controller.js'))).to be(true)
    expect(File.file?(File.join(dest, 'app/assets/stylesheets/upload_d_n_d/application.css'))).to be(true)
  end

  it 'est idempotent quand la copie est déjà à la bonne version' do
    src = make_source(version: '0.9.4')
    described_class.sync(source: src, dest: dest)

    expect(described_class.sync(source: src, dest: dest)).to eq(:unchanged)
  end

  it 'rafraîchit la copie lors d\'une montée de version' do
    described_class.sync(source: make_source(version: '0.9.3'), dest: dest)

    expect(described_class.sync(source: make_source(version: '0.9.4'), dest: dest)).to eq(:updated)
    expect(dest_version).to eq('0.9.4')
  end

  it 'remplace un ancien lien symbolique (gem <= 0.9.3) par une copie' do
    gem_dir = make_source(version: '0.9.4')
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.ln_s(gem_dir, dest)

    expect(described_class.sync(source: gem_dir, dest: dest)).to eq(:updated)
    expect(File.symlink?(dest)).to be(false)
    expect(File.directory?(dest)).to be(true)
    expect(File.file?(File.join(dest, 'package.json'))).to be(true)
  end

  it 'ne touche jamais à un dossier étranger (pas notre package.json)' do
    FileUtils.mkdir_p(dest)
    File.write(File.join(dest, 'package.json'), JSON.generate(name: 'autre', version: '1.0.0'))
    File.write(File.join(dest, 'garde.txt'), 'intact')

    expect(described_class.sync(source: make_source(version: '0.9.4'), dest: dest)).to eq(:conflict)
    expect(File.read(File.join(dest, 'garde.txt'))).to eq('intact') # rien supprimé
  end

  it 'ne touche jamais à un vrai fichier présent à cet emplacement' do
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, 'contenu')

    expect(described_class.sync(source: make_source(version: '0.9.4'), dest: dest)).to eq(:conflict)
    expect(File.read(dest)).to eq('contenu') # rien supprimé
  end
end
