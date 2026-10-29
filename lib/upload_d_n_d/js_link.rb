# frozen_string_literal: true

require "fileutils"

module UploadDND
  # Réconcilie le lien symbolique `node_modules/upload_d_n_d` utilisé par
  # jsbundling (bun/esbuild) et Tailwind pour résoudre `upload_d_n_d` et
  # `upload_d_n_d/styles` depuis le paquet de la gem.
  #
  # Idempotent, et corrige deux cas que la simple présence du lien masquait :
  # un lien périmé pointant vers une version précédente de la gem (montée de
  # version), et un lien cassé dont la cible a disparu (où `ln_s` échouerait,
  # le lien existant déjà).
  #
  # Ne gère que les liens symboliques. Un vrai dossier ou fichier à cet
  # emplacement (par ex. un paquet installé par npm) n'est jamais supprimé ni
  # écrasé : la méthode signale un conflit (`:conflict`) et laisse l'appelant
  # avertir.
  module JsLink
    module_function

    # Crée ou met à jour le lien `link_path` vers `target`.
    #
    # @param link_path [String, Pathname] emplacement du lien (node_modules/upload_d_n_d)
    # @param target [String, Pathname] répertoire cible (gem_dir de la gem courante)
    # @return [Symbol] :created, :updated, :unchanged ou :conflict
    def reconcile(link_path:, target:)
      link = link_path.to_s
      target = target.to_s

      if File.symlink?(link)
        return :unchanged if resolves_to?(link, target)

        File.unlink(link) # lien périmé, cassé, ou pointant ailleurs
        link!(link, target)
        :updated
      elsif File.exist?(link)
        :conflict # vrai dossier/fichier (ex. installé par npm) : on n'y touche jamais
      else
        link!(link, target)
        :created
      end
    end

    # Confronte la cible réelle du lien au dossier de la gem, après résolution
    # des deux chemins (chemin relatif, lien intermédiaire) : un lien qui pointe
    # déjà vers la bonne gem par un chemin indirect n'est pas remplacé. Un lien
    # cassé ne résout pas (ENOENT) et n'est donc jamais considéré comme à jour.
    def resolves_to?(link, target)
      File.realpath(link) == File.realpath(target)
    rescue Errno::ENOENT
      false
    end
    private_class_method :resolves_to?

    def link!(link, target)
      FileUtils.mkdir_p(File.dirname(link))
      FileUtils.ln_s(target, link)
    end
    private_class_method :link!
  end
end
