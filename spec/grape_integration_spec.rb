require "spec_helper"

RSpec.describe GrapeRailsLogger::GrapeInstrumentation do
  it "defines middleware class" do
    expect(defined?(GrapeRailsLogger::GrapeInstrumentation)).to eq("constant")
  end
end
