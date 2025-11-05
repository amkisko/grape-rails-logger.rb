require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe "parameter filtering" do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
    Rails.application.config.filter_parameters = [:password, :token]
  end

  it "filters parameters using Rails ParameterFilter" do
    app = Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation
      params do
        optional :username
        optional :password
      end
      post("/login") { {ok: true} }
    end

    Rack::MockRequest.new(app).post("/login", params: {username: "bob", password: "secret"})

    expect(logger.lines.any? { |o| o.is_a?(Hash) && o[:params].is_a?(Hash) && o[:params].values.any? { |v| v == "[FILTERED]" } }).to be true
  end
end
