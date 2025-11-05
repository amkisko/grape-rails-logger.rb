require "spec_helper"
require "rack/mock"

RSpec.describe "DB timing aggregation" do
  let(:logger_io) { StringIO.new }
  let(:logger) { Logger.new(logger_io) }

  before do
    Rails._logger = logger
  end

  it "aggregates sql.active_record durations and counts" do
    app = Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation
      get("/db") do
        ActiveSupport::Notifications.instrument("sql.active_record") { 1 + 1 }
        ActiveSupport::Notifications.instrument("sql.active_record") { 2 + 2 }
        {ok: true}
      end
    end

    received = nil
    req_sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }
    sql_sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      GrapeRailsLogger::Timings.append_db_runtime(ActiveSupport::Notifications::Event.new(*args))
    end

    Rack::MockRequest.new(app).get("/db")

    expect(received.payload[:db_calls]).to be >= 1
    expect(received.payload[:db_runtime]).to be_a(Numeric)
  ensure
    ActiveSupport::Notifications.unsubscribe(req_sub)
    ActiveSupport::Notifications.unsubscribe(sql_sub)
  end
end
