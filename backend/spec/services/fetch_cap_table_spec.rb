# frozen_string_literal: true

RSpec.describe FetchCapTable do
  let(:company) { create(:company, equity_enabled: true, fully_diluted_shares: 10000) }

  describe "#perform" do
    context "when company has equity enabled" do
      it "returns cap table structure" do
        service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: false)
        result = service.perform

        expect(result).to include(
          :investors,
          :fully_diluted_shares,
          :outstanding_shares,
          :option_pools,
          :share_classes,
          :all_share_classes,
          :exercise_prices
        )
      end

      it "returns company fully diluted shares" do
        service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: false)
        result = service.perform

        expect(result[:fully_diluted_shares]).to eq(10000)
      end

      context "with old schema" do
        let(:user) { create(:user, legal_name: "Test User", email: "test@example.com") }
        let(:company_investor) { create(:company_investor, company: company, user: user, total_shares: 1000) }

        before do
          create(:share_class, company: company, name: "Common")
        end

        it "includes investor user data" do
          service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: true)
          result = service.perform

          expect(result[:investors]).to be_an(Array)
        end

        it "excludes email for non-admin users" do
          service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: false)
          result = service.perform

          result[:investors].each do |investor|
            expect(investor).not_to have_key(:email)
          end
        end
      end

      context "with new schema" do
        let(:investor_entity) { create(:company_investor_entity, company: company, name: "Test Corp", email: "corp@example.com") }

        it "includes investor entity data" do
          service = described_class.new(company: company, new_schema: true, is_admin_or_lawyer: true)
          result = service.perform

          expect(result[:investors]).to be_an(Array)
        end
      end

      context "with convertible investments" do
        let!(:convertible) { create(:convertible_investment, company: company, entity_name: "Test SAFE") }

        it "includes convertible investments" do
          service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: false)
          result = service.perform

          expect(result[:investors]).to be_an(Array)
        end
      end
    end

    context "when company does not have equity enabled" do
      before do
        company.update!(equity_enabled: false)
      end

      it "returns empty array" do
        service = described_class.new(company: company, new_schema: false, is_admin_or_lawyer: false)
        result = service.perform

        expect(result).to eq([])
      end
    end
  end
end
