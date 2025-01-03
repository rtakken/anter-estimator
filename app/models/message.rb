class Message < ApplicationRecord
  include ActionView::RecordIdentifier
  belongs_to :conversation
  has_one_attached :image


  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[system user assistant] }

  after_create_commit -> { 
    broadcast_append_to "messages", 
    target:  "messages-table",
    partial: "conversations/message" }
end