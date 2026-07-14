class TwitchConfig < ApplicationRecord
  validates :channel_name, presence: true
end