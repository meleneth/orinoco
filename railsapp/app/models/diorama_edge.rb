class DioramaEdge < ApplicationRecord
  KINDS = %w[
    contains
    uses
    executes
    selects
    guards
    binds
    requires
    previews
    traces
  ].freeze

  belongs_to :diorama
  belongs_to :from_node, class_name: "DioramaNode", inverse_of: :outgoing_edges
  belongs_to :to_node, class_name: "DioramaNode", inverse_of: :incoming_edges

  validates :kind, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :kind, uniqueness: { scope: [ :diorama_id, :from_node_id, :to_node_id ] }

  validate :nodes_belong_to_diorama

  private

  def nodes_belong_to_diorama
    return if diorama_id.blank?

    if from_node&.diorama_id.present? && from_node.diorama_id != diorama_id
      errors.add(:from_node_id, "must belong to the same diorama")
    end

    if to_node&.diorama_id.present? && to_node.diorama_id != diorama_id
      errors.add(:to_node_id, "must belong to the same diorama")
    end
  end
end
