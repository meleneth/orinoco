class Diorama < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9._-]+\z/

  has_many :nodes, class_name: "DioramaNode", dependent: :destroy, inverse_of: :diorama
  has_many :edges, class_name: "DioramaEdge", dependent: :destroy, inverse_of: :diorama

  validates :slug, :name, :version, :visibility, presence: true
  validates :slug, uniqueness: true, format: { with: SLUG_FORMAT }

  def to_param
    slug
  end
end
