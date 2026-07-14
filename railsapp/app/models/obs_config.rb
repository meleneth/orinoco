class ObsConfig < ApplicationRecord
  after_initialize :set_defaults, if: :new_record?

  validates :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }

  private

  def set_defaults
    self.host ||= "host.docker.internal"
    self.port ||= 4455
  end
end