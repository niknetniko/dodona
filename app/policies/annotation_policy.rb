class AnnotationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.zeus?
        scope.all
      elsif user
        common = scope.joins(:submission)
        common.where(submissions: { user: user }).or(common.where(submissions: { course_id: user.administrating_courses.map(&:id) }))
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def create?
    user.course_admin?(record.submission.course)
  end

  def show?
    SubmissionPolicy.new(user, record.submission).show?
  end

  def update?
    record&.user == user
  end

  def destroy?
    record&.user == user
  end

  def permitted_attributes
    if record.class == Annotation
      %i[annotation_text]
    else # new record
      %i[annotation_text line_nr]
    end
  end
end
