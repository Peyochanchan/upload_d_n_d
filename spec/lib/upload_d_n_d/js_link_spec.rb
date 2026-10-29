# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'upload_d_n_d/js_link'

RSpec.describe UploadDND::JsLink do
  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  # node_modules/upload_d_n_d dans une fausse racine d'app.
  def link_path
    File.join(@root, 'node_modules', 'upload_d_n_d')
  end

  # Simule le répertoire d'une version de la gem (gem_dir).
  def gem_dir(name)
    File.join(@root, name).tap { |d| FileUtils.mkdir_p(d) }
  end

  it 'crée le lien quand node_modules/upload_d_n_d est absent' do
    target = gem_dir('upload_d_n_d-0.9.3')

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:created)
    expect(File.symlink?(link_path)).to be(true)
    expect(File.readlink(link_path)).to eq(target)
  end

  it 'est idempotent quand le lien pointe déjà vers la bonne cible' do
    target = gem_dir('upload_d_n_d-0.9.3')
    described_class.reconcile(link_path: link_path, target: target)

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:unchanged)
    expect(File.readlink(link_path)).to eq(target)
  end

  it 'ne remplace pas un lien qui résout vers la gem via un lien intermédiaire' do
    target = gem_dir('upload_d_n_d-0.9.3')
    alias_path = File.join(@root, 'alias')
    FileUtils.ln_s(target, alias_path)              # alias -> gem
    FileUtils.mkdir_p(File.dirname(link_path))
    FileUtils.ln_s(alias_path, link_path)           # node_modules/upload_d_n_d -> alias

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:unchanged)
    expect(File.readlink(link_path)).to eq(alias_path) # non remplacé
  end

  it 'ne remplace pas un lien à cible relative qui résout vers la gem' do
    target = gem_dir('upload_d_n_d-0.9.3')
    FileUtils.mkdir_p(File.dirname(link_path))
    Dir.chdir(File.dirname(link_path)) do           # cible relative depuis node_modules/
      File.symlink(File.join('..', 'upload_d_n_d-0.9.3'), 'upload_d_n_d')
    end

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:unchanged)
  end

  it 'remplace un lien vers une autre version encore présente sur le disque' do
    old = gem_dir('upload_d_n_d-0.8.0') # ancienne cible toujours présente (cas réel 0.8.0)
    neu = gem_dir('upload_d_n_d-0.9.3')
    described_class.reconcile(link_path: link_path, target: old)

    expect(described_class.reconcile(link_path: link_path, target: neu)).to eq(:updated)
    expect(File.readlink(link_path)).to eq(neu)
    expect(File.directory?(old)).to be(true) # l'ancien dossier de gem n'est pas supprimé
  end

  it 'remplace un lien cassé dont la cible a disparu' do
    old = gem_dir('upload_d_n_d-0.9.2')
    described_class.reconcile(link_path: link_path, target: old)
    FileUtils.remove_entry(old)

    expect(File.symlink?(link_path)).to be(true)
    expect(File.exist?(link_path)).to be(false) # lien cassé

    neu = gem_dir('upload_d_n_d-0.9.3')
    expect(described_class.reconcile(link_path: link_path, target: neu)).to eq(:updated)
    expect(File.readlink(link_path)).to eq(neu)
  end

  it 'ne touche jamais à un vrai dossier (ex. paquet npm) et signale un conflit' do
    FileUtils.mkdir_p(link_path)
    marker = File.join(link_path, 'package.json')
    File.write(marker, '{"name":"autre"}')
    target = gem_dir('upload_d_n_d-0.9.3')

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:conflict)
    expect(File.symlink?(link_path)).to be(false)
    expect(File.directory?(link_path)).to be(true)
    expect(File.read(marker)).to eq('{"name":"autre"}') # rien supprimé
  end

  it 'ne touche jamais à un vrai fichier présent à cet emplacement' do
    FileUtils.mkdir_p(File.dirname(link_path))
    File.write(link_path, 'contenu')
    target = gem_dir('upload_d_n_d-0.9.3')

    expect(described_class.reconcile(link_path: link_path, target: target)).to eq(:conflict)
    expect(File.symlink?(link_path)).to be(false)
    expect(File.file?(link_path)).to be(true)
    expect(File.read(link_path)).to eq('contenu') # rien supprimé
  end
end
