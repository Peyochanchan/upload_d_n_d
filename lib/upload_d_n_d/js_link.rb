# frozen_string_literal: true

require "fileutils"
require "json"

module UploadDND
  # Synchronise `node_modules/upload_d_n_d` avec le JS/CSS de la gem
  # (`package.json` + les fichiers de ses `exports`) en les **copiant**.
  #
  # Pourquoi une copie et non un lien symbolique : le JS de la gem importe des
  # bibliothèques tierces (`@hotwired/stimulus`, `@rails/activestorage`) que
  # l'app hôte fournit dans ses propres `node_modules`. Un lien symbolique est
  # résolu vers son `realpath` (le dossier de la gem, hors de l'app) et la
  # résolution de ces imports y échoue. Un vrai dossier sous les `node_modules`
  # de l'app laisse la résolution remonter jusqu'aux dépendances de l'app.
  #
  # La copie est rafraîchie quand la version de la gem change. Un dossier ou
  # fichier **non géré par la gem** (ex. paquet installé par npm) n'est jamais
  # supprimé : la méthode signale un conflit et laisse l'appelant avertir.
  module JsLink
    PACKAGE_NAME = "upload_d_n_d"

    module_function

    # Copie/rafraîchit le JS de la gem depuis `source` (gem_dir) vers `dest`
    # (node_modules/upload_d_n_d).
    #
    # @param source [String, Pathname] répertoire de la gem (gem_dir)
    # @param dest [String, Pathname] destination dans node_modules
    # @return [Symbol] :created, :updated, :unchanged ou :conflict
    def sync(source:, dest:)
      source = source.to_s
      dest = dest.to_s

      if File.symlink?(dest)
        replace(source, dest) # ancien lien symbolique (gem <= 0.9.3)
        :updated
      elsif File.directory?(dest)
        return :conflict unless ours?(dest) # dossier étranger : on n'y touche jamais
        return :unchanged if up_to_date?(source, dest)

        replace(source, dest) # notre copie, contenu périmé
        :updated
      elsif File.exist?(dest)
        :conflict # fichier étranger
      else
        copy(source, dest)
        :created
      end
    end

    # Le dossier est-il une copie gérée par la gem (et non un paquet étranger) ?
    def ours?(dest)
      pkg = File.join(dest, "package.json")
      File.file?(pkg) && read_json(pkg)["name"] == PACKAGE_NAME
    rescue JSON::ParserError
      false
    end
    private_class_method :ours?

    # Compare le CONTENU (pas seulement la version du package.json) : une gem
    # branchée en `path:`/`git:` peut garder la même version tout en changeant le
    # JS. La copie est à jour si chaque fichier attendu existe et est identique.
    def up_to_date?(source, dest)
      package_files(source).all? do |rel|
        target = File.join(dest, rel)
        File.file?(target) && FileUtils.identical?(File.join(source, rel), target)
      end
    end
    private_class_method :up_to_date?

    def replace(source, dest)
      FileUtils.remove_entry(dest)
      copy(source, dest)
    end
    private_class_method :replace

    # Copie `package.json` et les fichiers référencés par ses `exports`, en
    # conservant leurs chemins relatifs (les `exports` les désignent ainsi).
    def copy(source, dest)
      package_files(source).each do |rel|
        from = File.join(source, rel)
        to = File.join(dest, rel)
        FileUtils.mkdir_p(File.dirname(to))
        FileUtils.cp(from, to)
      end
    end
    private_class_method :copy

    def package_files(source)
      exports = read_json(File.join(source, "package.json"))["exports"] || {}
      targets = []
      collect = lambda do |value|
        case value
        when String then targets << value
        when Hash then value.each_value(&collect)
        end
      end
      exports.each_value(&collect)

      files = [ "package.json" ]
      targets.each do |target|
        rel = target.sub(%r{\A\./}, "")
        if rel.include?("*")
          Dir.glob(File.join(source, rel)).each { |path| files << path.sub("#{source}/", "") }
        else
          files << rel
        end
      end
      files.uniq
    end
    private_class_method :package_files

    def read_json(path)
      JSON.parse(File.read(path))
    end
    private_class_method :read_json
  end
end
