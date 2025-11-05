require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe "Status extraction edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }
  let(:middleware) { GrapeRailsLogger::GrapeInstrumentation.new(nil) }

  describe "subscriber status extraction" do
    it "extracts status from endpoint, payload, exception, and response in priority order" do
      endpoint = double("Endpoint", status: 201, respond_to?: true)
      exception = double("Exception", status: 403, respond_to?: true)
      allow(exception).to receive(:is_a?).and_return(false)

      # Payload status takes highest priority
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint},
        status: 404,
        exception_object: exception,
        response: [500, {}, []]
      })
      expect(subscriber.send(:extract_status, event)).to eq(404)

      # Response status when payload status missing
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint},
        exception_object: exception,
        response: [500, {}, []]
      })
      expect(subscriber.send(:extract_status, event)).to eq(500)

      # Exception status when response and payload missing
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint},
        exception_object: exception
      })
      expect(subscriber.send(:extract_status, event)).to eq(403)

      # Endpoint status as last resort (only for error statuses >= 400)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })
      # Endpoint status 201 won't be used (only >= 400), so defaults to 200
      expect(subscriber.send(:extract_status, event)).to eq(200)

      # Test endpoint status with error status (>= 400)
      error_endpoint = double("Endpoint", status: 404, respond_to?: true)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => error_endpoint}
      })
      expect(subscriber.send(:extract_status, event)).to eq(404)
    end

    it "handles invalid status values and defaults to 200" do
      endpoint = double("Endpoint", status: "201", respond_to?: true)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })
      expect(subscriber.send(:extract_status, event)).to eq(200)

      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:status).and_return(false)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })
      expect(subscriber.send(:extract_status, event)).to eq(200)
    end
  end

  describe "middleware response status extraction" do
    it "extracts status from array response" do
      status = middleware.send(:extract_status_from_response, [404, {}, []])
      expect(status).to eq(404)
    end

    it "extracts status from response object with status method" do
      response_obj = double("Response", status: 418)
      status = middleware.send(:extract_status_from_response, response_obj)
      expect(status).to eq(418)
    end

    it "returns nil for unknown response types" do
      status = middleware.send(:extract_status_from_response, "string response")
      expect(status).to be_nil

      status = middleware.send(:extract_status_from_response, Object.new)
      expect(status).to be_nil
    end

    it "returns nil for response object with non-integer status" do
      response_obj = Struct.new(:status).new("200")
      status = middleware.send(:extract_status_from_response, response_obj)
      expect(status).to be_nil
    end
  end
end
