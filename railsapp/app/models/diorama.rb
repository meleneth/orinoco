class Diorama < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9._-]+\z/

  has_many :nodes, class_name: "DioramaNode", dependent: :destroy, inverse_of: :diorama
  has_many :edges, class_name: "DioramaEdge", dependent: :destroy, inverse_of: :diorama

  validates :slug, :name, :version, :visibility, presence: true
  validates :slug, uniqueness: true, format: { with: SLUG_FORMAT }

  def to_param
    slug
  end

  def self.suggested_slug(name)
    base = slug_segment(name.presence || "diorama")
    slug = base
    suffix = 2

    while exists?(slug: slug)
      slug = "#{base}_#{suffix}"
      suffix += 1
    end

    slug
  end

  def self.slug_segment(value)
    value.to_s.parameterize(separator: "_").presence || "diorama"
  end
end
