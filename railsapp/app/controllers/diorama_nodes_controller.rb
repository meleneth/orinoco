class DioramaNodesController < ApplicationController
  before_action :load_diorama
  before_action :load_node, only: [ :show, :edit, :update ]
  before_action :load_neighborhood, only: [ :show, :edit, :update ]
  before_action :load_creation_context, only: [ :new, :create ]

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

  def new
    return if performed?

    @node = build_new_node
    @editor = DioramaNodeForms.build(@node)
    render :new
  end

  def create
    return if performed?

    @node = build_new_node
    @editor = DioramaNodeForms.build(@node)
    @editor.assign_attributes(node_params)

    @node.slug = DioramaNode.suggested_slug(
      diorama: @diorama,
      kind: @child_kind,
      name: @editor.name
    )

    created = false

    ActiveRecord::Base.transaction do
      if @editor.save
        edge = DioramaEdge.new(
          diorama: @diorama,
          from_node: @parent_node,
          to_node: @node,
          kind: @edge_kind
        )
        if edge.save
          created = true
        else
          edge.errors.full_messages.each { |message| @editor.errors.add(:base, message) }
          raise ActiveRecord::Rollback
        end
      else
        raise ActiveRecord::Rollback
      end
    end

    if created
      redirect_to edit_diorama_node_path(@diorama, @node), notice: "#{@node.name} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_diorama
    @diorama = Diorama.find_by!(slug: params[:diorama_id])
  end

  def load_node
    @node = @diorama.nodes.find_by!(slug: params[:id])
  end

  def load_creation_context
    @parent_node = @diorama.nodes.find_by!(slug: params[:parent_node_slug])
    @edge_kind = params[:edge_kind].to_s

    if @edge_kind.blank?
      render plain: "edge_kind is required", status: :bad_request
      return
    end

    @child_kind = Dioramas::EdgeKinds.child_kind_for(@edge_kind, parent_kind: @parent_node.kind)

    if @child_kind.blank?
      render plain: "Unsupported edge kind for child creation", status: :bad_request
      return
    end

    requested_kind = params[:kind].presence
    if requested_kind.present? && requested_kind != @child_kind
      render plain: "Requested child kind does not match edge kind", status: :bad_request
      return
    end
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

  def build_new_node
    DioramaNode.new(
      diorama: @diorama,
      kind: @child_kind
    )
  end
end
