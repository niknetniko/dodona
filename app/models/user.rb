# == Schema Information
#
# Table name: users
#
#  id             :integer          not null, primary key
#  username       :string(255)
#  first_name     :string(255)
#  last_name      :string(255)
#  email          :string(255)
#  permission     :integer          default("0")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  lang           :string(255)      default("nl")
#  token          :string(255)
#  time_zone      :string(255)      default("Brussels")
#  institution_id :bigint
#  search         :string(4096)
#

require 'securerandom'

class User < ApplicationRecord
  include Filterable
  include StringHelper
  include Cacheable
  include Tokenable
  include ActiveModel::Dirty

  ATTEMPTED_EXERCISES_CACHE_STRING = '/courses/%<course_id>s/user/%<id>s/attempted_exercises'.freeze
  CORRECT_EXERCISES_CACHE_STRING = '/courses/%<course_id>s/user/%<id>s/correct_exercises'.freeze

  enum permission: { student: 0, staff: 1, zeus: 2 }

  belongs_to :institution, optional: true

  has_many :api_tokens, dependent: :restrict_with_error
  has_many :submissions, dependent: :restrict_with_error
  has_many :course_memberships, dependent: :restrict_with_error
  has_many :repository_admins, dependent: :restrict_with_error
  has_many :courses, through: :course_memberships
  has_many :events, dependent: :restrict_with_error
  has_many :exports, dependent: :destroy
  has_many :notifications, dependent: :destroy

  has_many :subscribed_courses,
           lambda {
             where.not course_memberships:
                           { status: %i[pending unsubscribed] }
           },
           through: :course_memberships,
           source: :course

  has_many :favorite_courses,
           lambda {
             where.not course_memberships:
                           { status: %i[pending unsubscribed] }
             where course_memberships:
                       { favorite: true }
           },
           through: :course_memberships,
           source: :course

  has_many :administrating_courses,
           lambda {
             where course_memberships:
                       { status: :course_admin }
           },
           through: :course_memberships,
           source: :course

  has_many :enrolled_courses,
           lambda {
             where course_memberships:
                       { status: :student }
           },
           through: :course_memberships,
           source: :course

  has_many :pending_courses,
           lambda {
             where course_memberships:
                       { status: :pending }
           },
           through: :course_memberships,
           source: :course

  has_many :unsubscribed_courses,
           lambda {
             where course_memberships:
                       { status: :unsubscribed }
           },
           through: :course_memberships,
           source: :course

  has_many :repositories,
           through: :repository_admins,
           source: :repository

  has_many :annotations, dependent: :restrict_with_error

  devise :saml_authenticatable
  devise :omniauthable, omniauth_providers: %i[smartschool office365 google_oauth2]

  validates :username, uniqueness: { case_sensitive: false, allow_blank: true, scope: :institution }
  validates :email, uniqueness: { case_sensitive: false, allow_blank: true }
  validate :email_only_blank_if_smartschool

  token_generator :token

  before_save :set_token
  before_save :set_time_zone
  before_save :split_last_name, unless: :first_name?, if: :last_name?
  before_update :check_permission_change
  before_save :nullify_empty_username

  scope :by_permission, ->(permission) { where(permission: permission) }
  scope :by_institution, ->(institution) { where(institution: institution) }

  scope :in_course, ->(course) { joins(:course_memberships).where('course_memberships.course_id = ?', course.id) }
  scope :by_course_labels, ->(labels, course_id) { where(id: CourseMembership.where(course_id: course_id).by_course_labels(labels).select(:user_id)) }
  scope :at_least_one_started_in_series, ->(series) { where(id: Submission.where(course_id: series.course_id, exercise_id: series.exercises).select('DISTINCT(user_id)')) }
  scope :at_least_one_started_in_course, ->(course) { where(id: Submission.where(course_id: course.id, exercise_id: course.exercises).select('DISTINCT(user_id)')) }

  def email_only_blank_if_smartschool
    errors.add(:email, 'should not be blank when institution does not use smartschool') if email.blank? && !institution&.smartschool?
  end

  def full_name
    name = (first_name || '') + ' ' + (last_name || '')
    first_string_present name, 'n/a'
  end

  def pretty_email
    if first_name || last_name
      "#{full_name} <#{email}>"
    else
      email
    end
  end

  def first_name
    return self[:first_name] unless Current.demo_mode && Current.user != self

    Faker::Config.random = Random.new(id + Date.today.yday)
    Faker::Name.first_name
  end

  def last_name
    return self[:last_name] unless Current.demo_mode && Current.user != self

    Faker::Config.random = Random.new(id + Date.today.yday)
    Faker::Name.last_name
  end

  def username
    return self[:username] unless Current.demo_mode && Current.user != self

    (first_name[0] + last_name[0, 7]).downcase
  end

  def email
    return self[:email] unless Current.demo_mode && Current.user != self

    "#{first_name}.#{last_name}@dodona.ugent.be"
  end

  def short_name
    first_string_present username, first_name, full_name
  end

  def admin?
    staff? || zeus?
  end

  def course_admin?(course)
    zeus? || admin_of?(course)
  end

  def a_course_admin?
    admin? || administrating_courses.any?
  end

  def repository_admin?(repository)
    zeus? || repositories.pluck(:id).include?(repository.id)
  end

  def attempted_exercises(options)
    s = submissions.judged
    s = s.in_course(options[:course]) if options[:course].present?
    s.select('distinct exercise_id').count
  end

  invalidateable_instance_cacheable(:attempted_exercises,
                                    ->(this, options) { format(ATTEMPTED_EXERCISES_CACHE_STRING, course_id: options[:course].present? ? options[:course].id.to_s : 'global', id: this.id.to_s) })

  def correct_exercises(options)
    s = submissions.where(status: :correct)
    s = s.in_course(options[:course]) if options[:course].present?
    s.select('distinct exercise_id').count
  end

  invalidateable_instance_cacheable(:correct_exercises,
                                    ->(this, options) { format(CORRECT_EXERCISES_CACHE_STRING, course_id: options[:course].present? ? options[:course].id.to_s : 'global', id: this.id.to_s) })

  def unfinished_exercises(course = nil)
    attempted_exercises(course: course) - correct_exercises(course: course)
  end

  def recent_exercises(limit = 3)
    submissions.select('distinct exercise_id').limit(limit).map(&:exercise)
  end

  def pending_series
    courses.map { |c| c.pending_series(self) }.flatten.sort_by(&:deadline)
  end

  def homepage_series
    subscribed_courses.map { |c| c.homepage_series(0) }.flatten.sort_by(&:deadline)
  end

  def recent_courses(number_of_years)
    grouped_recent_courses(number_of_years).map { |a| a[1] }.flatten
  end

  def grouped_recent_courses(number_of_years)
    return [] if subscribed_courses.empty?

    subscribed_courses.group_by(&:year).first(number_of_years)
  end

  def full_view?
    subscribed_courses.count > 4 || subscribed_courses.group_by(&:year).length > 1 || favorite_courses.count.positive?
  end

  def member_of?(course)
    course.present? && subscribed_courses.pluck(:id).include?(course.id)
  end

  def admin_of?(course)
    course.present? && administrating_courses.pluck(:id).include?(course.id)
  end

  def membership_status_for(course)
    membership = CourseMembership.find_by(course: course, user: self)
    if membership
      membership.status
    else
      'no_membership'
    end
  end

  # update and return user using an omniauth authentication hash
  def update_from_oauth(oauth_hash, auth_inst)
    tap do |user|
      user.username = oauth_hash.uid
      user.email = oauth_hash.info.email
      user.first_name = oauth_hash.info.first_name
      user.last_name = oauth_hash.info.last_name
      user.institution = auth_inst if user.institution.nil?
      user.save
    end
  end

  def self.from_institution(auth, institution)
    # try to look up existing users
    # using username and institution
    user = find_by(username: auth.uid, institution: institution)
    # create a new user within the institution
    # if nothing was found
    user = new(institution: institution) if user.nil?
    user
  end

  def self.from_email(email)
    return nil if email.blank?

    find_by(email: email)
  end

  def set_search
    self.search = "#{username || ''} #{first_name || ''} #{last_name || ''}"
  end

  private

  def set_token
    if institution.present?
      self.token = nil
    elsif token.blank?
      generate_token
    end
  end

  def set_time_zone
    self.time_zone = 'Seoul' if email&.match?(/ghent.ac.kr$/)
  end

  def check_permission_change
    Event.create(event_type: :permission_change, user: self, message: "Granted #{permission}#{Current.user ? " by #{Current.user.full_name} (id: #{Current.user.id})" : ''}") if permission_changed?
  end

  def nullify_empty_username
    self.username = nil if username.blank?
  end

  def split_last_name
    parts = last_name.split(' ', 2)
    return unless parts.count == 2

    self.first_name = parts[0]
    self.last_name = parts[1]
  end
end
