# frozen_string_literal: true

# Policy Pundit pour l'upload de fichiers permanents avec UploadDND
#
# Cette policy contrôle qui peut attacher et supprimer des fichiers
# sur des records existants (via le moteur UploadDND).
#
# Le controller du moteur autorise via `authorize :upload_d_n_d_attachment`
# (record symbolique), ce qui amène Pundit à chercher cette classe.
#
class UploadDNDAttachmentPolicy < ApplicationPolicy
  # Détermine qui peut attacher un fichier à un record existant
  #
  # Par défaut : tous les utilisateurs authentifiés
  # Exemples de personnalisation :
  #   - Seulement les admins : user&.admin?
  #   - Seulement certains rôles : user&.admin? || user&.editor?
  #
  def create?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user.present?
  end

  # Détermine qui peut modifier les fichiers d'un record
  #
  def update?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user.present?
  end

  # Détermine qui peut supprimer un fichier d'un record
  #
  def destroy?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user.present?
  end
end
