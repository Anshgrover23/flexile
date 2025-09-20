# frozen_string_literal: true

class Internal::Companies::Administrator::CapTablesController < Internal::Companies::BaseController
  def show
    authorize :cap_table

    new_schema = params[:new_schema] == "true"
    is_admin_or_lawyer = current_user.company_administrator?(Current.company) ||
                        current_user.company_lawyer?(Current.company)

    result = FetchCapTable.new(
      company: Current.company,
      new_schema: new_schema,
      is_admin_or_lawyer: is_admin_or_lawyer
    ).perform

    presenter = CapTablePresenter.new(result)
    render json: presenter.props
  end

  def create
    authorize :cap_table

    result = CreateCapTable.new(
      company: Current.company,
      investors_data: cap_table_params[:investors]
    ).perform

    if result[:success]
      head :created
    else
      render json: { success: false, errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  private
    def cap_table_params
      params.require(:cap_table).permit(investors: [:userId, :shares])
    end
end
