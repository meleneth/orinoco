class DioramasController < ApplicationController
  def index
    @dioramas = Diorama.includes(:nodes).order(:name)
    @default_clip_show = Diorama.find_by(slug: Dioramas::Defaults::ClipShow::DIORAMA_ATTRIBUTES[:slug])
  end

  def show
    @diorama = Diorama.includes(:nodes, :edges).find_by!(slug: params[:id])
    @root_nodes = @diorama.nodes.where(kind: "affordance").order(:slug)
    @nodes_by_kind = grouped_nodes
  end

  def bootstrap_default
    diorama = Dioramas::Defaults::ClipShow.find_or_create!
    redirect_to diorama_path(diorama), notice: "Default Clip Show is ready."
  end

  private

  def grouped_nodes
    ordered = DioramaNode::KINDS.index_with { [] }

    @diorama.nodes.each do |node|
      next if node.kind == "affordance"

      ordered[node.kind] ||= []
      ordered[node.kind] << node
    end

    ordered.transform_values { |nodes| nodes.sort_by(&:slug) }.reject { |_kind, nodes| nodes.empty? }
  end
end
