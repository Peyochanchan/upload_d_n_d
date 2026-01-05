# frozen_string_literal: true

# Policy Pundit pour l'upload de fichiers temporaires avec UploadDND
#
# Cette policy contrôle qui peut uploader et supprimer des fichiers temporaires.
# Personnalisez les méthodes ci-dessous selon vos besoins d'autorisation.
#
class UploadDNDTemporaryAttachmentPolicy < ApplicationPolicy
  # Détermine qui peut créer (uploader) un fichier temporaire
  #
  # Par défaut : tous les utilisateurs authentifiés
  # Exemples de personnalisation :
  #   - Seulement les admins : user&.admin?
  #   - Seulement certains rôles : user&.admin? || user&.editor?
  #   - Selon un attribut : user&.can_upload?
  #
  def create?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user.present?
  end

  # Détermine qui peut supprimer un fichier temporaire
  #
  # Par défaut : tous les utilisateurs authentifiés
  # La vérification de propriété (session) est déjà faite dans le controller
  #
  def destroy?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user.present?
  end

  # Détermine qui peut nettoyer les fichiers temporaires expirés
  # (utilisé par les tâches cron/jobs)
  #
  def cleanup?
    # PERSONNALISEZ CETTE MÉTHODE selon vos besoins
    user&.admin?
  end

  # Exemple d'autorisation plus stricte (commenté par défaut)
  # Décommentez et adaptez selon vos besoins
  #
  # def create?
  #   return false unless user.present?
  #
  #   # Seulement les admins et éditeurs
  #   user.admin? || user.editor?
  # end
  #
  # def destroy?
  #   return false unless user.present?
  #
  #   # Seulement les admins, éditeurs, ou l'équipe régionale
  #   user.admin? || user.editor? || user.team&.regional_team?
  # end
end
