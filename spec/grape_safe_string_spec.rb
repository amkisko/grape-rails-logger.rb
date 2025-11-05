require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "safe_string helper edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  it "returns nil for nil value" do
    result = subscriber.send(:safe_string, nil)
    expect(result).to be_nil
  end

  it "converts value to string" do
    result = subscriber.send(:safe_string, 123)
    expect(result).to eq("123")
  end

  it "handles objects that raise on to_s" do
    problematic = double("Object")
    allow(problematic).to receive(:to_s).and_raise(StandardError, "to_s failed")

    result = subscriber.send(:safe_string, problematic)
    expect(result).to be_nil
  end

  it "handles symbol values" do
    result = subscriber.send(:safe_string, :get)
    expect(result).to eq("get")
  end

  it "handles string values" do
    result = subscriber.send(:safe_string, "test")
    expect(result).to eq("test")
  end
end
