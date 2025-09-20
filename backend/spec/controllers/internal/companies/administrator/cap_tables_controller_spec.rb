# frozen_string_literal: true

RSpec.describe Internal::Companies::Administrator::CapTablesController do
  let(:company) { create(:company, equity_enabled: true, share_price_in_usd: 10.0, fully_diluted_shares: 0) }
  let(:user) { create(:user) }
  let(:company_administrator) { create(:company_administrator, company: company, user: user) }
  let(:investors_data) do
    [
      { userId: user.external_id, shares: 100_000 }
    ]
  end

  before do
    allow(controller).to receive(:authenticate_user_json!).and_return(true)

    allow(controller).to receive(:current_context) do
      Current.user = user
      Current.company = company
      Current.company_administrator = company_administrator
      CurrentContext.new(user: user, company: company)
    end
  end

  describe "POST #create" do
    context "when user is authorized" do
      before do
        company_administrator
      end

      context "when service succeeds" do
        before do
          allow(CreateCapTable).to receive(:new).and_return(
            double(perform: { success: true, errors: [] })
          )
        end

        it "calls the service with correct parameters" do
          expect(CreateCapTable).to receive(:new) do |args|
            expect(args[:company]).to eq(company)
            expect(args[:investors_data].first["userId"]).to eq(user.external_id)
            expect(args[:investors_data].first["shares"]).to eq("100000")
            double(perform: { success: true, errors: [] })
          end

          post :create, params: { company_id: company.external_id, cap_table: { investors: investors_data } }
          expect(response).to have_http_status(:created)
        end
      end

      context "when service fails" do
        before do
          allow(CreateCapTable).to receive(:new).and_return(
            double(perform: { success: false, errors: ["Some error message"] })
          )
        end

        it "calls the service with correct parameters" do
          expect(CreateCapTable).to receive(:new) do |args|
            expect(args[:company]).to eq(company)
            expect(args[:investors_data].first["userId"]).to eq(user.external_id)
            expect(args[:investors_data].first["shares"]).to eq("100000")
            double(perform: { success: false, errors: ["Some error message"] })
          end

          post :create, params: { company_id: company.external_id, cap_table: { investors: investors_data } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body).to eq({
            "success" => false,
            "errors" => ["Some error message"],
          })
        end
      end
    end

    context "when user is not authorized" do
      before { company_administrator.destroy! }

      it "disallows access" do
        post :create, params: { company_id: company.external_id, cap_table: { investors: investors_data } }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when company already has existing cap table data" do
      before do
        company_administrator
        create(:share_class, company: company, name: "Series A")
      end

      it "returns forbidden status due to authorization policy" do
        post :create, params: { company_id: company.external_id, cap_table: { investors: investors_data } }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET #show" do
    let(:company_investor) { create(:company_investor, company: company, user: user) }

    context "when user is authorized as administrator" do
      it "returns cap table data" do
        service_double = instance_double(FetchCapTable)
        expected_result = {
          investors: [{ name: "Test", id: "123" }],
          fully_diluted_shares: 1000,
          outstanding_shares: 1000,
          option_pools: [],
          share_classes: [],
          all_share_classes: [],
          exercise_prices: [],
        }

        allow(FetchCapTable).to receive(:new)
          .with(company: company, new_schema: false, is_admin_or_lawyer: true)
          .and_return(service_double)
        allow(service_double).to receive(:perform).and_return(expected_result)

        get :show, params: { company_id: company.external_id }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(expected_result.with_indifferent_access)
      end

      it "handles new_schema parameter" do
        allow(FetchCapTable).to receive(:new)
          .with(company: company, new_schema: true, is_admin_or_lawyer: true)
          .and_return(instance_double(FetchCapTable, perform: {}))

        get :show, params: { company_id: company.external_id, new_schema: "true" }

        expect(FetchCapTable).to have_received(:new).with(
          company: company, new_schema: true, is_admin_or_lawyer: true
        )
      end
    end

    context "when user is authorized as lawyer" do
      let(:lawyer_user) { create(:user) }
      let(:company_lawyer) { create(:company_lawyer, company: company, user: lawyer_user) }

      before do
        allow(controller).to receive(:current_user).and_return(lawyer_user)
      end

      it "returns cap table data" do
        allow(FetchCapTable).to receive(:new)
          .with(company: company, new_schema: false, is_admin_or_lawyer: true)
          .and_return(instance_double(FetchCapTable, perform: { investors: [] }))

        get :show, params: { company_id: company.external_id }

        expect(response).to have_http_status(:ok)
      end
    end

    context "when user is authorized as investor" do
      let(:investor_user) { create(:user) }

      before do
        create(:company_investor, company: company, user: investor_user)
        allow(controller).to receive(:current_user).and_return(investor_user)
      end

      it "returns cap table data" do
        allow(FetchCapTable).to receive(:new)
          .with(company: company, new_schema: false, is_admin_or_lawyer: false)
          .and_return(instance_double(FetchCapTable, perform: { investors: [] }))

        get :show, params: { company_id: company.external_id }

        expect(response).to have_http_status(:ok)
      end
    end

    context "when company does not have equity enabled" do
      before do
        company.update!(equity_enabled: false)
      end

      it "returns forbidden status" do
        get :show, params: { company_id: company.external_id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when user is not authorized" do
      it "returns forbidden status" do
        company_administrator.destroy!

        get :show, params: { company_id: company.external_id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
