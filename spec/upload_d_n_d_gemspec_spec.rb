# frozen_string_literal: true

require 'rails_helper'

# Garde sur le contenu publié de la gem (cf. B4) : la liste de fichiers du
# gemspec ne doit embarquer ni dépendances JS vendorées ni le Minitest, et doit
# inclure le CHANGELOG.
RSpec.describe 'upload_d_n_d.gemspec' do
  let(:gemspec) { Gem::Specification.load(File.expand_path('../upload_d_n_d.gemspec', __dir__)) }
  let(:files) { gemspec.files }

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
end
