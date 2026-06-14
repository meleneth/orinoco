class DioramasController < ApplicationController
  def index
    load_index_data
  end

  def show
    @diorama = Diorama.includes(:nodes, :edges).find_by!(slug: params[:id])
    @root_nodes = @diorama.nodes.where(kind: "affordance").includes(:outgoing_edges).order(:slug)
  end

  def bootstrap_default
    diorama = Dioramas::Defaults::ClipShow.find_or_create!
    redirect_to diorama_path(diorama), notice: "Default Clip Show is ready."
  end

  def export
    diorama = Diorama.includes(:nodes, :edges).find_by!(slug: params[:id])

    send_data Dioramas::JsonExporter.new(diorama).to_json,
              filename: "#{diorama.slug}.json",
              type: "application/json",
              disposition: "attachment"
  end

  def import
    diorama = Dioramas::JsonImporter.call(import_params[:file], name: import_params[:name])

    redirect_to diorama_path(diorama), notice: "Imported diorama as #{diorama.name}."
  rescue Dioramas::ImportError => e
    load_index_data
    flash.now[:alert] = e.message
    render :index, status: :unprocessable_entity
  end

  private

  def load_index_data
    @dioramas = Diorama.includes(:nodes).order(:name)
    @default_clip_show = Diorama.find_by(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug])
  end

  def import_params
    params.fetch(:diorama_import, ActionController::Parameters.new).permit(:name, :file)
  end
end
