require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger do
  describe ".config" do
    it "returns a Config instance" do
      expect(GrapeRailsLogger.config).to be_a(GrapeRailsLogger::Config)
    end

    it "returns the same instance on subsequent calls" do
      first = GrapeRailsLogger.config
      second = GrapeRailsLogger.config
      expect(first).to be(second)
    end
  end

  describe ".configure" do
    it "yields the config object" do
      config_obj = nil
      GrapeRailsLogger.configure do |config|
        config_obj = config
      end
      expect(config_obj).to be_a(GrapeRailsLogger::Config)
      expect(config_obj).to be(GrapeRailsLogger.config)
    end

    it "allows configuring enabled" do
      GrapeRailsLogger.configure do |config|
        config.enabled = false
      end
      expect(GrapeRailsLogger.config.enabled).to be false
    end

    it "allows configuring subscriber_class" do
      custom_subscriber = Class.new
      GrapeRailsLogger.configure do |config|
        config.subscriber_class = custom_subscriber
      end
      expect(GrapeRailsLogger.config.subscriber_class).to be(custom_subscriber)
    end

    it "allows configuring logger" do
      custom_logger = TestLogger.new
      GrapeRailsLogger.configure do |config|
        config.logger = custom_logger
      end
      expect(GrapeRailsLogger.config.logger).to be(custom_logger)
    end

    it "allows configuring tag" do
      GrapeRailsLogger.configure do |config|
        config.tag = "CustomTag"
      end
      expect(GrapeRailsLogger.config.tag).to eq("CustomTag")
    end
  end

  describe ".effective_config" do
    context "when Rails is available" do
      before do
        allow(Rails).to receive(:application).and_return(Rails.application)
        allow(Rails.application.config).to receive(:respond_to?).with(:grape_rails_logger).and_return(true)
      end

      it "uses Rails config when available" do
        rails_config = double(
          enabled: false,
          subscriber_class: Class.new,
          logger: TestLogger.new,
          tag: "RailsTag",
          respond_to?: true
        )
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        effective = GrapeRailsLogger.effective_config
        expect(effective.enabled).to be false
        expect(effective.subscriber_class).to be(rails_config.subscriber_class)
        expect(effective.logger).to be(rails_config.logger)
        expect(effective.tag).to eq("RailsTag")
      end

      it "handles missing Rails config attributes gracefully" do
        rails_config = double(respond_to?: true)
        allow(rails_config).to receive(:respond_to?).with(:enabled).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:subscriber_class).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:logger).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:tag).and_return(false)
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        effective = GrapeRailsLogger.effective_config
        expect(effective.enabled).to be true # Default from Config.new
        expect(effective.subscriber_class).to eq(GrapeRailsLogger::GrapeRequestLogSubscriber)
      end

      it "handles nil Rails config values" do
        rails_config = double(
          enabled: nil,
          subscriber_class: nil,
          logger: nil,
          tag: nil,
          respond_to?: true
        )
        allow(rails_config).to receive(:respond_to?).with(:enabled).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:subscriber_class).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:logger).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:tag).and_return(true)
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        effective = GrapeRailsLogger.effective_config
        expect(effective.enabled).to be_nil
        expect(effective.subscriber_class).to be_nil
        expect(effective.logger).to be_nil
        expect(effective.tag).to be_nil
      end
    end

    context "when Rails.application is nil" do
      before do
        allow(Rails).to receive(:application).and_return(nil)
      end

      it "falls back to module-level config" do
        effective = GrapeRailsLogger.effective_config
        expect(effective).to be(GrapeRailsLogger.config)
      end
    end

    context "when Rails config doesn't respond to grape_rails_logger" do
      before do
        allow(Rails).to receive(:application).and_return(Rails.application)
        allow(Rails.application.config).to receive(:respond_to?).with(:grape_rails_logger).and_return(false)
      end

      it "falls back to module-level config" do
        effective = GrapeRailsLogger.effective_config
        expect(effective).to be(GrapeRailsLogger.config)
      end
    end
  end

  describe GrapeRailsLogger::Config do
    describe "#initialize" do
      it "sets default values" do
        config = GrapeRailsLogger::Config.new
        expect(config.enabled).to be true
        expect(config.subscriber_class).to eq(GrapeRailsLogger::GrapeRequestLogSubscriber)
        expect(config.logger).to be_nil
        expect(config.tag).to eq("Grape")
      end
    end

    describe "attribute accessors" do
      it "allows setting and getting enabled" do
        config = GrapeRailsLogger::Config.new
        config.enabled = false
        expect(config.enabled).to be false
      end

      it "allows setting and getting subscriber_class" do
        config = GrapeRailsLogger::Config.new
        custom_class = Class.new
        config.subscriber_class = custom_class
        expect(config.subscriber_class).to be(custom_class)
      end

      it "allows setting and getting logger" do
        config = GrapeRailsLogger::Config.new
        logger = TestLogger.new
        config.logger = logger
        expect(config.logger).to be(logger)
      end

      it "allows setting and getting tag" do
        config = GrapeRailsLogger::Config.new
        config.tag = "Custom"
        expect(config.tag).to eq("Custom")
      end
    end
  end
end
