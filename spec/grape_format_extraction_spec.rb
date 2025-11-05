require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "Format extraction edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  it "extracts format from request.try(:format)" do
    request = double("Request")
    allow(request).to receive(:try).with(:format).and_return(".json")
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("json")
  end

  it "extracts format from api.format env" do
    request = double("Request", env: {"api.format" => "xml"})
    allow(request).to receive(:try).with(:format).and_return(nil)
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("xml")
  end

  it "extracts format from rack.request.formats" do
    request = double("Request", env: {"rack.request.formats" => [".json"]})
    allow(request).to receive(:try).with(:format).and_return(nil)
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("json")
  end

  it "defaults to json when format is not found" do
    request = double("Request", env: {})
    allow(request).to receive(:try).with(:format).and_return(nil)
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("json")
  end

  it "removes leading dot from format" do
    request = double("Request", env: {"api.format" => ".json"})
    allow(request).to receive(:try).with(:format).and_return(nil)
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("json")
  end

  it "downcases format" do
    request = double("Request", env: {"api.format" => "JSON"})
    allow(request).to receive(:try).with(:format).and_return(nil)
    format = subscriber.send(:extract_format, request)
    expect(format).to eq("json")
  end
end
