# == Schema Information
#
# Table name: series
#
#  id          :integer          not null, primary key
#  course_id   :integer
#  name        :string(255)
#  description :text(65535)
#  visibility  :integer
#  order       :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  deadline    :datetime
#  token       :string(255)
#

class Series < ApplicationRecord
  enum visibility: [:open, :hidden, :closed]

  belongs_to :course
  has_many :series_memberships
  has_many :exercises, through: :series_memberships

  validates :course, presence: true
  validates :name, presence: true

  default_scope { order(created_at: :desc) }

  def deadline?
    !deadline.blank?
  end

  def zip_solutions(user)
    filename = "#{name.parameterize}-#{user.full_name.parameterize}.zip"
    stringio = Zip::OutputStream.write_buffer do |zio|
      exercises.each do |ex|
        submission = ex.best_last_submission(user, deadline)
        zio.put_next_entry(ex.file_name)
        zio.write submission&.code
      end
    end
    stringio.rewind
    zip_data = stringio.sysread
    { filename: filename, data: zip_data }
  end
end
