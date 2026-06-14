class DioramasController < ApplicationController
  def index
    @dioramas = Diorama.includes(:nodes).order(:name)
    @default_clip_show = Diorama.find_by(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug])
  end

  def show
    @diorama = Diorama.includes(:nodes, :edges).find_by!(slug: params[:id])
    @root_nodes = @diorama.nodes.where(kind: "affordance").includes(:outgoing_edges).order(:slug)
  end

  def bootstrap_default
    diorama = Dioramas::Defaults::ClipShow.find_or_create!
    redirect_to diorama_path(diorama), notice: "Default Clip Show is ready."
  end

  private
end
