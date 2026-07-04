class ClientUsageLog < ApplicationRecord
  belongs_to :client

  validates :period, presence: true
  validates :period, uniqueness: { scope: :client_id }
end
