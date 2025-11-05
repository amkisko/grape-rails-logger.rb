require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger::EndpointPatch do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  describe "#build_stack" do
    it "wraps app with EndpointWrapper when enabled" do
      allow(GrapeRailsLogger).to receive(:effective_config).and_return(
        double(enabled: true, logger: nil)
      )

      # Create a test class that prepends the patch (like Grape::Endpoint does)

      test_class = Class.new do
        prepend GrapeRailsLogger::EndpointPatch

        def build_stack(*args)
          ->(env) { [200, {}, ["OK"]] }
        end
      end

      instance = test_class.new
      app = instance.build_stack

      expect(app).to be_a(GrapeRailsLogger::EndpointWrapper)
      expect(app.instance_variable_get(:@endpoint)).to be(instance)
    end

    it "returns unwrapped app when disabled" do
      allow(GrapeRailsLogger).to receive(:effective_config).and_return(
        double(enabled: false, logger: nil)
      )

      test_class = Class.new do
        prepend GrapeRailsLogger::EndpointPatch

        def build_stack(*args)
          ->(env) { [200, {}, ["OK"]] }
        end
      end

      instance = test_class.new
      app = instance.build_stack

      # When disabled, should return the unwrapped app (not EndpointWrapper)
      expect(app).not_to be_a(GrapeRailsLogger::EndpointWrapper)
      expect(app).to respond_to(:call)
    end

    it "passes arguments through correctly" do
      received_args = nil

      test_class = Class.new do
        prepend GrapeRailsLogger::EndpointPatch

        define_method(:build_stack) do |*args|
          received_args = args
          ->(env) { [200, {}, ["OK"]] }
        end
      end

      allow(GrapeRailsLogger).to receive(:effective_config).and_return(
        double(enabled: true, logger: nil)
      )

      instance = test_class.new
      instance.build_stack(:arg1, :arg2, :arg3)

      expect(received_args).to eq([:arg1, :arg2, :arg3])
    end
  end
end
