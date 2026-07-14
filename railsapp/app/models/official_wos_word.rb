# frozen_string_literal: true

class OfficialWosWord < ApplicationRecord
  before_validation :normalize_word
  before_validation :assign_length
  before_validation :assign_metadata

  validates :word, presence: true, uniqueness: true, format: { with: /\A[A-Z]+\z/ }
  validates :length, numericality: { only_integer: true, greater_than: 0 }

  scope :with_length, ->(length) { where(length: Integer(length)) }

  private

  def normalize_word
    self.word = word.to_s.strip.upcase
  end

  def assign_length
    self.length = word.length if word.present?
  end

  def assign_metadata
    self.metadata ||= {}
  end
end