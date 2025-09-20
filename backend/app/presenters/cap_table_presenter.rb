# frozen_string_literal: true

class CapTablePresenter
  attr_reader :result

  def initialize(result)
    @result = result
  end

  def props
    {
      investors: investors_data,
      fully_diluted_shares: result[:fully_diluted_shares],
      outstanding_shares: result[:outstanding_shares],
      option_pools: result[:option_pools],
      share_classes: result[:share_classes],
      all_share_classes: result[:all_share_classes],
      exercise_prices: result[:exercise_prices],
    }
  end

  private
    def investors_data
      result[:investors].map do |investor|
        investor_data = {
          name: investor[:name],
        }

        # Add investor-specific fields if present
        investor_data[:id] = investor[:id] if investor.key?(:id)
        investor_data[:user_id] = investor[:user_id] if investor.key?(:user_id)
        investor_data[:outstanding_shares] = investor[:outstanding_shares] if investor.key?(:outstanding_shares)
        investor_data[:total_options] = investor[:total_options] if investor.key?(:total_options)
        investor_data[:fully_diluted_shares] = investor[:fully_diluted_shares] if investor.key?(:fully_diluted_shares)
        investor_data[:email] = investor[:email] if investor.key?(:email)
        investor_data[:shares_by_class] = investor[:shares_by_class] if investor.key?(:shares_by_class)
        investor_data[:options_by_strike] = investor[:options_by_strike] if investor.key?(:options_by_strike)

        investor_data
      end
    end
end
