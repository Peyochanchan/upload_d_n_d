# frozen_string_literal: true

# Ces controllers existent uniquement pour les specs.
#
# Objectif: éviter les "anonymous controllers" (Class.new) qui, sous Rails 7.2+,
# peuvent avoir `name=nil` ⇒ `controller_name=nil`, ce qui casse un hook interne
# de RSpec Rails (il fait `@controller.controller_name.to_sym`).
#
# En utilisant des constantes nommées (et namespacées), on reste aligné sur les
# conventions Rails/RSpec, sans monkeypatch.

class UploadableTestController < ActionController::Base
  include UploadDND::Controllers::Uploadable

  def index
    render json: { success: true }
  end

  def test_attach_files
    user = User.find(params[:id])
    attach_upload_d_n_d_files(user, params[:attribute_name])
    render json: { success: true }
  end

  def test_namespace
    render json: { namespace: send(:controller_namespace) }
  end

  def test_find_record
    record = send(:find_record_for_upload, params[:model_name], params[:record_id])
    render json: { id: record.id }
  end

  # Pundit (si présent dans l'app hôte) définit `authorize` sur les controllers.
  # Dans la gem, on veut tester l'appel; on fournit donc une implémentation
  # minimale pour permettre les expectations RSpec.
  def authorize(*)
    true
  end
end

module Admin
  class ProjectsController < UploadableTestController; end

  module Nested
    class ProjectsController < UploadableTestController; end
  end
end
