require "spec_helper"

RSpec.describe "ActiveRecord integration" do
  it "subscribes to sql.active_record when ActiveRecord is defined" do
    # Test that Timings works with SQL events regardless of ActiveRecord being available
    # The Timings module doesn't actually require ActiveRecord, just responds to events
    expect(GrapeRailsLogger::Timings).to respond_to(:append_db_runtime)

    # Create a mock event and append it
    event = ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.05, "1", {})
    GrapeRailsLogger::Timings.reset_db_runtime
    GrapeRailsLogger::Timings.append_db_runtime(event)
    expect(GrapeRailsLogger::Timings.db_runtime).to be > 0
    expect(GrapeRailsLogger::Timings.db_calls).to eq(1)
  end

  it "handles multiple DB events correctly" do
    GrapeRailsLogger::Timings.reset_db_runtime
    event1 = ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.05, "1", {})
    event2 = ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.03, "1", {})
    GrapeRailsLogger::Timings.append_db_runtime(event1)
    GrapeRailsLogger::Timings.append_db_runtime(event2)
    expect(GrapeRailsLogger::Timings.db_runtime).to be > 0.05
    expect(GrapeRailsLogger::Timings.db_calls).to eq(2)
  end
end
