# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tmpdir'
require 'stringio'

# Couvre le comportement d'affichage de la tâche (le détail filesystem de la
# réconciliation est couvert par UploadDND::JsLink).
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

  def link_path
    File.join(@root, 'node_modules', 'upload_d_n_d')
  end

  def gem_dir(name)
    File.join(@root, name).tap { |d| FileUtils.mkdir_p(d) }
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

  it 'affiche un message et crée le lien quand il est absent' do
    out, err = invoke(gem_dir: gem_dir('upload_d_n_d-0.9.3'))

    expect(out).to include('linked JS')
    expect(err).to be_empty
    expect(File.symlink?(link_path)).to be(true)
  end

  it 'n\'affiche rien quand le lien est déjà correct' do
    target = gem_dir('upload_d_n_d-0.9.3')
    invoke(gem_dir: target)

    out, err = invoke(gem_dir: target)

    expect(out).to be_empty
    expect(err).to be_empty
  end

  it 'avertit sans rien supprimer quand un vrai dossier occupe l\'emplacement' do
    FileUtils.mkdir_p(link_path)
    File.write(File.join(link_path, 'package.json'), '{}')

    out, err = invoke(gem_dir: gem_dir('upload_d_n_d-0.9.3'))

    expect(out).to be_empty
    expect(err).to match(/n'est pas un lien géré/)
    expect(File.symlink?(link_path)).to be(false)
    expect(File.directory?(link_path)).to be(true)
  end
end
