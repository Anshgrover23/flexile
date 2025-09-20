# frozen_string_literal: true

RSpec.describe CapTablePresenter do
  let(:result) do
    {
      investors: [{ name: "Test Investor", id: "123", email: "test@example.com" }],
      fully_diluted_shares: 1000,
      outstanding_shares: 1000,
      option_pools: [{ name: "Pool", available_shares: 100 }],
      share_classes: [{ id: 1, name: "Common", outstanding_shares: 1000, fully_diluted_shares: 1100 }],
      all_share_classes: ["Common"],
      exercise_prices: ["$5.00"],
    }
  end

  subject(:presenter) { described_class.new(result) }

  describe "#props" do
    it "returns complete props structure" do
      props = presenter.props

      expect(props).to include(
        :investors,
        :fully_diluted_shares,
        :outstanding_shares,
        :option_pools,
        :share_classes,
        :all_share_classes,
        :exercise_prices
      )
    end

    it "preserves top-level data" do
      props = presenter.props

      expect(props[:fully_diluted_shares]).to eq(1000)
      expect(props[:option_pools]).to eq([{ name: "Pool", available_shares: 100 }])
    end

    it "includes investor fields when present" do
      investor = presenter.props[:investors].first

      expect(investor).to include(
        name: "Test Investor",
        id: "123",
        email: "test@example.com"
      )
    end

    it "conditionally includes optional investor fields" do
      minimal_result = {
        investors: [{ name: "Basic Investor" }],
        fully_diluted_shares: 1000,
        outstanding_shares: 1000,
        option_pools: [],
        share_classes: [],
        all_share_classes: [],
        exercise_prices: [],
      }

      presenter = described_class.new(minimal_result)
      investor = presenter.props[:investors].first

      expect(investor).to have_key(:name)
      expect(investor).not_to have_key(:id)
      expect(investor).not_to have_key(:email)
    end

    context "with empty investors" do
      let(:result) do
        {
          investors: [],
          fully_diluted_shares: 0,
          outstanding_shares: 0,
          option_pools: [],
          share_classes: [],
          all_share_classes: [],
          exercise_prices: [],
        }
      end

      it "returns empty investors array" do
        expect(presenter.props[:investors]).to eq([])
      end
    end
  end
end
