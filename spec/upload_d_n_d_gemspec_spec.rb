# frozen_string_literal: true

require 'rails_helper'
require 'json'
require 'tmpdir'
require 'rubygems/package'

# Garde sur le contenu publié de la gem (cf. B4) : la liste de fichiers du
# gemspec ne doit embarquer ni dépendances JS vendorées ni le Minitest, doit
# inclure le CHANGELOG, et doit embarquer `package.json` + les fichiers de ses
# `exports` (sans quoi jsbundling/Tailwind ne résolvent plus `upload_d_n_d`).
RSpec.describe 'upload_d_n_d.gemspec' do
  let(:gemspec) { Gem::Specification.load(File.expand_path('../upload_d_n_d.gemspec', __dir__)) }
  let(:files) { gemspec.files }
  let(:root) { File.expand_path('..', __dir__) }

  # Cibles concrètes déclarées dans les "exports" de package.json (globs étendus).
  let(:exported_files) do
    pkg = JSON.parse(File.read(File.join(root, 'package.json')))
    targets = []
    collect = lambda do |value|
      case value
      when String then targets << value
      when Hash then value.each_value(&collect)
      end
    end
    pkg.fetch('exports').each_value(&collect)

    targets.flat_map do |rel|
      clean = rel.sub(%r{\A\./}, '')
      if clean.include?('*')
        Dir.glob(File.join(root, clean)).map { |p| p.sub("#{root}/", '') }
      else
        [ clean ]
      end
    end.uniq
  end

  it 'ships no vendored node_modules' do
    expect(files.grep(%r{\Anode_modules/})).to be_empty
  end

  it 'ships no Minitest files' do
    expect(files.grep(%r{\Atest/(?!dummy/)})).to be_empty
  end

  it 'ships the changelog' do
    expect(files).to include('docs/CHANGELOG.md')
  end

  it 'version matches the gem' do
    expect(gemspec.version.to_s).to eq(UploadDND::VERSION)
  end

  it 'ships package.json' do
    expect(files).to include('package.json')
  end

  it 'ships the root styles.css entry point (Tailwind 3 / postcss-import)' do
    expect(files).to include('styles.css')
  end

  it 'ships every file referenced by package.json exports' do
    expect(exported_files).not_to be_empty
    expect(files).to include(*exported_files)
  end

  it 'builds a .gem that contains package.json and the exported files' do
    # `gem build` valide et empaquette relativement au cwd : on construit depuis
    # la racine du projet, puis on retire le .gem produit.
    built = nil
    Dir.chdir(root) do
      built = Gem::Package.build(gemspec)
      contents = Gem::Package.new(built).contents

      expect(contents).to include('package.json')
      expect(contents).to include(*exported_files)
    end
  ensure
    FileUtils.rm_f(File.join(root, built)) if built
  end
end
