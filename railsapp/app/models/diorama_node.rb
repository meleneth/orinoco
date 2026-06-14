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

  before_validation :assign_slug, on: :create

  def wrapper
    DioramaNodeTypes.wrap(self)
  end

  def to_param
    slug
  end

  def self.suggested_slug(diorama:, kind:, name:)
    base = [ kind.presence || "node", slug_segment(name.presence || kind.presence || "node") ].join(".")
    slug = base
    suffix = 2

    while diorama.nodes.exists?(slug: slug)
      slug = "#{base}_#{suffix}"
      suffix += 1
    end

    slug
  end

  def self.slug_segment(value)
    value.to_s.parameterize(separator: "_").presence || "node"
  end

  private

  def assign_slug
    return if slug.present?
    return if diorama.blank? || kind.blank?

    self.slug = self.class.suggested_slug(
      diorama: diorama,
      kind: kind,
      name: name
    )
  end
end
