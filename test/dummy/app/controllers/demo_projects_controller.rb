# Démonstration du composant dans un navigateur : création (fichiers
# temporaires) et édition (record existant).
class DemoProjectsController < ApplicationController
  include UploadDND::Controllers::Uploadable
  # Helper installé dans l'app hôte par le générateur (upload_d_n_d:install)
  helper UploadDND::UploadHelper

  before_action :set_demo_project, only: [ :show, :edit, :update ]

  def index
    @demo_projects = DemoProject.order(created_at: :desc)
  end

  def show; end

  def new
    @demo_project = DemoProject.new
  end

  def create
    @demo_project = DemoProject.new(demo_project_params)
    wire_temporary_uploads(@demo_project)

    if @demo_project.save
      redirect_to @demo_project
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @demo_project.update(demo_project_params)
      redirect_to @demo_project
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_demo_project
    @demo_project = DemoProject.find(params[:id])
  end

  def demo_project_params
    params.require(:demo_project).permit(:name)
  end
end
