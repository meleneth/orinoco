class DioramaNode < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9._-]+\z/
  KINDS = %w[
    affordance
    rule
    trigger
    selector
    condition
    effect
    asset
    placement
    binding
    capability
    test_event
    runtime_trace
  ].freeze

  belongs_to :diorama

  has_many :outgoing_edges,
           class_name: "DioramaEdge",
           foreign_key: :from_node_id,
           dependent: :destroy,
           inverse_of: :from_node
  has_many :incoming_edges,
           class_name: "DioramaEdge",
           foreign_key: :to_node_id,
           dependent: :destroy,
           inverse_of: :to_node

  validates :slug, :kind, :name, presence: true
  validates :slug, uniqueness: { scope: :diorama_id }, format: { with: SLUG_FORMAT }
  validates :kind, inclusion: { in: KINDS }

  def wrapper
    DioramaNodeTypes.wrap(self)
  end

  def to_param
    slug
  end
end
