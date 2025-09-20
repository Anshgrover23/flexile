# frozen_string_literal: true

class CapTablePolicy < ApplicationPolicy
  def show?
    return false unless company.equity_enabled?
    company_administrator? || company_lawyer? || company_investor?
  end

  def create?
    return false unless company_administrator?
    company.cap_table_empty?
  end
end
