# frozen_string_literal: true

class FetchCapTable
  def initialize(company:, new_schema: false, is_admin_or_lawyer: false)
    @company = company
    @new_schema = new_schema
    @is_admin_or_lawyer = is_admin_or_lawyer
    @outstanding_shares = 0
  end

  def perform
    return [] unless @company.equity_enabled?

    investors = []
    investors.concat(fetch_investor_entities) if @new_schema
    investors.concat(fetch_investor_users) unless @new_schema
    investors.concat(fetch_convertible_investments)

    # Add breakdown data to each investor
    add_breakdown_data_to_investors(investors)

    {
      investors: investors,
      fully_diluted_shares: @company.fully_diluted_shares,
      outstanding_shares: @outstanding_shares,
      option_pools: fetch_option_pools,
      share_classes: fetch_share_classes,
      all_share_classes: fetch_share_classes.map { |sc| sc[:name] },
      exercise_prices: fetch_exercise_prices.map { |price| "$#{price.to_f.round(2)}" },
    }
  end

    private
      def fetch_investor_entities
        entities = @company.company_investor_entities
                          .select(
                            :external_id,
                            :name,
                            :total_shares,
                            :email,
                            "COALESCE((" +
                              "SELECT SUM(vested_shares + unvested_shares) " +
                              "FROM equity_grants " +
                              "WHERE equity_grants.company_investor_entity_id = company_investor_entities.id" +
                            "), 0) as total_options"
                          )
                          .where("total_shares > 0 OR (COALESCE((" +
                            "SELECT SUM(vested_shares + unvested_shares) " +
                            "FROM equity_grants " +
                            "WHERE equity_grants.company_investor_entity_id = company_investor_entities.id" +
                          "), 0)) > 0")
                          .order("total_shares DESC, total_options DESC")

        entities.map do |entity|
          fully_diluted_shares = entity.total_shares.to_i + entity.total_options.to_i
          @outstanding_shares += entity.total_shares.to_i

          investor_data = {
            id: entity.external_id,
            name: entity.name,
            outstanding_shares: entity.total_shares.to_i,
            total_options: entity.total_options.to_i,
            fully_diluted_shares: fully_diluted_shares,
            shares_by_class:,
            options_by_strike:,
          }

          @is_admin_or_lawyer ? investor_data.merge(email: entity.email) : investor_data
        end
      end

      def fetch_investor_users
        investors = @company.company_investors
                           .joins(:user)
                           .select(
                             "company_investors.external_id",
                             "users.external_id as user_id",
                             "COALESCE(users.legal_name, '') as name",
                             "company_investors.total_shares",
                             "users.email",
                             "COALESCE((" +
                               "SELECT SUM(vested_shares + unvested_shares) " +
                               "FROM equity_grants " +
                               "WHERE equity_grants.company_investor_id = company_investors.id" +
                             "), 0) as total_options"
                           )
                           .where("company_investors.total_shares > 0 OR (COALESCE((" +
                             "SELECT SUM(vested_shares + unvested_shares) " +
                             "FROM equity_grants " +
                             "WHERE equity_grants.company_investor_id = company_investors.id" +
                           "), 0)) > 0")
                           .order("company_investors.total_shares DESC, total_options DESC")

        investors.map do |investor|
          fully_diluted_shares = investor.total_shares.to_i + investor.total_options.to_i
          @outstanding_shares += investor.total_shares.to_i

          investor_data = {
            id: investor.external_id,
            user_id: investor.user_id,
            name: investor.name,
            outstanding_shares: investor.total_shares.to_i,
            total_options: investor.total_options.to_i,
            fully_diluted_shares: fully_diluted_shares,
            shares_by_class:,
            options_by_strike:,
          }

          @is_admin_or_lawyer ? investor_data.merge(email: investor.email) : investor_data
        end
      end

      def fetch_convertible_investments
        @company.convertible_investments
                .select("CONCAT(entity_name, ' ', convertible_type) as name")
                .order(implied_shares: :desc)
                .map do |investment|
          {
            name: investment.name,
            shares_by_class:,
            options_by_strike:,
          }
        end
      end

      def fetch_option_pools
        @company.option_pools
                .select(:name, :available_shares)
                .map { |pool| { name: pool.name, available_shares: pool.available_shares } }
      end

      def fetch_share_classes
        share_classes = @company.share_classes
                               .select(:id, :name)
                               .includes(:share_holdings, option_pools: :equity_grants)

        share_classes.map do |share_class|
          outstanding_shares = share_class.share_holdings.sum(:number_of_shares)

          pool_ids = share_class.option_pools.pluck(:id)
          exercisable_shares = EquityGrant.where(option_pool_id: pool_ids)
                                         .sum("vested_shares + unvested_shares")

          {
            id: share_class.id,
            name: share_class.name,
            outstanding_shares: outstanding_shares,
            fully_diluted_shares: outstanding_shares + exercisable_shares,
          }
        end
      end

      def fetch_exercise_prices
        @company.equity_grants
                .joins(:option_pool)
                .distinct
                .order(:exercise_price_usd)
                .pluck(:exercise_price_usd)
      end

      def add_breakdown_data_to_investors(investors)
        share_classes = fetch_share_classes
        exercise_prices = fetch_exercise_prices

        investors.each do |investor|
          next unless investor.key?(:id) # Skip SAFE investments

          # Get shares by class
          shares_by_class = {}
          share_classes.each do |share_class|
            if @new_schema
              total = ShareHolding.joins(:company_investor_entity)
                                 .where(company_investor_entities: { external_id: investor[:id] })
                                 .where(share_class_id: share_class[:id])
                                 .sum(:number_of_shares)
            else
              total = ShareHolding.joins(:company_investor)
                                 .where(company_investors: { external_id: investor[:id] })
                                 .where(share_class_id: share_class[:id])
                                 .sum(:number_of_shares)
            end
            shares_by_class[share_class[:name]] = total
          end

          # Get options by strike price
          options_by_strike = {}
          exercise_prices.each do |price|
            if @new_schema
              total = EquityGrant.joins(:option_pool, :company_investor_entity)
                                .where(company_investor_entities: { external_id: investor[:id] })
                                .where(exercise_price_usd: price)
                                .where(option_pools: { company_id: @company.id })
                                .sum(:vested_shares)
            else
              total = EquityGrant.joins(:option_pool, :company_investor)
                                .where(company_investors: { external_id: investor[:id] })
                                .where(exercise_price_usd: price)
                                .where(option_pools: { company_id: @company.id })
                                .sum(:vested_shares)
            end
            options_by_strike["$#{price.to_f.round(2)}"] = total
          end

          investor[:shares_by_class] = shares_by_class
          investor[:options_by_strike] = options_by_strike
        end
      end
end
