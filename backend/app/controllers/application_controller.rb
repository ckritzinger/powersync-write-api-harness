class ApplicationController < ActionController::Base
  before_action :set_refresh

  rescue_from StandardError, with: :source_unavailable if Rails.env.production?

  private

  # ?refresh=N re-renders every N seconds; ?refresh=0 turns it off. Remembered per page via the URL.
  def set_refresh
    @refresh = params.fetch(:refresh, 3).to_i.clamp(0, 3600)
  end

  def source_unavailable(error)
    @error = error
    render "layouts/error", status: :service_unavailable
  end

  # Raw stored values (no ORM type casting), so the oracle shows exactly what the write API wrote.
  def stored_attrs(record)
    if record.respond_to?(:attributes_before_type_cast)
      record.attributes_before_type_cast
    else
      record.attributes
    end
  end
  helper_method :stored_attrs

  # Timestamps with milliseconds and zone, so sub-second write ordering is visible.
  def show_value(value)
    value.respond_to?(:iso8601) ? value.iso8601(3) : value
  end
  helper_method :show_value
end
