class LabelPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope
    end
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    user&.admin?
  end

  def update?
    user&.zeus?
  end

  def destroy?
    user&.zeus?
  end

  def permitted_attributes
    %i[name]
  end
end
