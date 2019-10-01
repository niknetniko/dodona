# == Schema Information
#
# Table name: events
#
#  id         :bigint           not null, primary key
#  event_type :integer          not null
#  user_id    :integer
#  message    :string(255)      not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

FactoryBot.define do
  factory :event do
    event_type { Event.event_types.keys.sample }
    user
    message { Faker::Lorem.words 5 }
  end
end
