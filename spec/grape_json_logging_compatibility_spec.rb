require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe "grape-rails-logger compatibility with JsonLogging" do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  context "without JsonLogging gem" do
    it "works with plain Rails.logger and Hash messages" do
      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::GrapeInstrumentation
        get("/test") { {ok: true} }
      end

      Rack::MockRequest.new(app).get("/test")

      expect(logger.lines).not_to be_empty
      entry = logger.lines.last
      expect(entry).to be_a(Hash)
      expect(entry[:method]).to eq("GET")
      expect(entry[:path]).to eq("/test")
      expect(entry[:status]).to eq(200)
    end

    it "logs error messages as Hash" do
      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::GrapeInstrumentation
        get("/error") { error!("nope", 400) }
      end

      Rack::MockRequest.new(app).get("/error")

      expect(logger.lines).not_to be_empty
      entry = logger.lines.last
      expect(entry).to be_a(Hash)
      expect(entry[:status]).to be_a(Integer)
    end
  end

  context "with JsonLogging gem" do
    before do
      # Simulate JsonLogging being available
      unless defined?(JsonLogging)
        module JsonLogging
          def self.new(logger)
            logger
          end
        end
      end
    end

    it "works seamlessly with JsonLogging wrapped logger" do
      # Mock JsonLogging to return the logger wrapped
      wrapped_logger = Class.new do
        def initialize(base)
          @base = base
        end

        def info(hash)
          @base.info(hash) if hash.is_a?(Hash)
        end

        def error(hash)
          @base.error(hash) if hash.is_a?(Hash)
        end
      end.new(logger)

      allow(Rails).to receive(:logger).and_return(wrapped_logger)

      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::GrapeInstrumentation
        get("/test") { {ok: true} }
      end

      Rack::MockRequest.new(app).get("/test")

      expect(logger.lines).not_to be_empty
      entry = logger.lines.last
      expect(entry).to be_a(Hash)
      expect(entry[:method]).to eq("GET")
    end
  end

  it "does not require JsonLogging to be loaded" do
    # Ensure JsonLogging is not in the load path
    expect(defined?(JsonLogging)).to be_falsey unless Object.const_defined?(:JsonLogging, false)

    app = Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation
      get("/test") { {ok: true} }
    end

    expect { Rack::MockRequest.new(app).get("/test") }.not_to raise_error
    expect(logger.lines).not_to be_empty
  end
end
