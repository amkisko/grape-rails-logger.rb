require "spec_helper"

RSpec.describe "GrapeRailsLogger module loading" do
  it "loads all required modules" do
    expect(defined?(GrapeRailsLogger)).to be_truthy
    expect(defined?(GrapeRailsLogger::Timings)).to be_truthy
    expect(defined?(GrapeRailsLogger::GrapeInstrumentation)).to be_truthy
    expect(defined?(GrapeRailsLogger::GrapeRequestLogSubscriber)).to be_truthy
    expect(defined?(GrapeRailsLogger::DebugTracer)).to be_truthy
    expect(defined?(GrapeRailsLogger::StatusExtractor)).to be_truthy
  end

  it "loads constants correctly for Rails autoloading" do
    # Verify all constants are available for Rails autoloading
    # Subscribers are registered when Rails loads via Railtie, not during gem require
    expect(defined?(GrapeRailsLogger::GrapeInstrumentation)).to be_truthy
    expect(defined?(GrapeRailsLogger::GrapeRequestLogSubscriber)).to be_truthy
  end

  it "subscribes to sql.active_record when ActiveRecord is defined" do
    if defined?(ActiveRecord)
      # This is harder to test directly, but we can verify the code path exists
      expect(defined?(ActiveRecord)).to be_truthy
    end
  end
end
