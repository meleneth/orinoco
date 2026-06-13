class DioramaNodesController < ApplicationController
  before_action :load_diorama
  before_action :load_node
  before_action :load_neighborhood

  def show
    load_editor
    render :show
  end

  def edit
    load_editor
    render :show
  end

  def update
    load_editor
    @editor.assign_attributes(node_params)

    if @editor.save
      redirect_to diorama_node_path(@diorama, @node), notice: "#{@node.name} updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_diorama
    @diorama = Diorama.find_by!(slug: params[:diorama_id])
  end

  def load_node
    @node = @diorama.nodes.find_by!(slug: params[:id])
  end

  def load_editor
    @editor = DioramaNodeForms.build(@node)
  end

  def load_neighborhood
    @neighborhood = Dioramas::GraphNeighborhood.call(@node)
  end

  def node_params
    params.fetch(:diorama_node_form, ActionController::Parameters.new).permit(
      :name,
      :description,
      :event,
      :selector,
      :args_input_uuid,
      :condition,
      :args_affordance,
      :args_scene_name,
      :effect,
      :args_scene_item_id,
      :enabled,
      :asset_type,
      :image_storage,
      :image_media_type,
      :image_encoding,
      :image_data,
      :image_asset_ref,
      :image_sha256,
      :image_byte_size,
      :image_width,
      :image_height,
      :raw_data
    )
  end
end
