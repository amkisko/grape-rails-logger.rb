require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "Exception data building edge cases" do
  let(:logger) { TestLogger.new }
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  before do
    Rails._logger = logger
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
  end

  it "includes backtrace in non-production environments" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    exception = StandardError.new("Test error")
    exception.set_backtrace(["file.rb:1", "file.rb:2", "file.rb:3"] * 5) # More than 10 lines

    data = subscriber.send(:build_exception_data, exception)
    expect(data[:backtrace]).to be_a(Array)
    expect(data[:backtrace].length).to eq(10) # Limited to 10
  end

  it "excludes backtrace in production environment" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    exception = StandardError.new("Test error")
    exception.set_backtrace(["file.rb:1"])

    data = subscriber.send(:build_exception_data, exception)
    expect(data[:backtrace]).to be_nil
  end

  it "handles exception without backtrace" do
    exception = StandardError.new("No backtrace")
    allow(exception).to receive(:backtrace).and_return(nil)

    data = subscriber.send(:build_exception_data, exception)
    expect(data[:class]).to eq("StandardError")
    expect(data[:message]).to eq("No backtrace")
    expect(data[:backtrace]).to be_nil
  end

  it "handles exception data extraction failure" do
    exception = double("Exception")
    allow(exception).to receive(:class).and_raise(StandardError, "Failed")
    allow(exception).to receive(:name).and_return("StandardError")
    allow(exception).to receive(:message).and_raise(StandardError, "Failed")

    data = subscriber.send(:build_exception_data, exception)
    expect(data[:class]).to eq("Unknown")
    expect(data[:message]).to include("Failed to extract exception data")
  end

  it "handles exception without message method" do
    exception = Class.new(StandardError) do
      undef_method :message
    end.new

    data = subscriber.send(:build_exception_data, exception)
    expect(data[:class]).to eq("Unknown")
    expect(data[:message]).to include("Failed to extract exception data")
  end
end
