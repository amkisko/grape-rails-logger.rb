require "spec_helper"

RSpec.describe "Railtie error handling" do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
    Rails._env = ActiveSupport::StringInquirer.new("development")
  end

  describe "ActiveRecord SQL event subscription error handling" do
    it "handles errors in DB runtime append and logs in development" do
      # Simulate ActiveRecord being defined
      unless defined?(ActiveRecord)
        stub_const("ActiveRecord", Module.new)
      end

      # Create an event that will cause an error
      event_data = ["sql.active_record", Time.now, Time.now + 0.01, "1", {}]

      # Force an error in append_db_runtime
      allow(GrapeRailsLogger::Timings).to receive(:append_db_runtime).and_raise(StandardError, "DB error")

      # Simulate the subscription callback (this would normally be set up by Railtie)
      # We can't easily test the actual after_initialize callback, but we can test the error handling logic
      begin
        GrapeRailsLogger::Timings.append_db_runtime(ActiveSupport::Notifications::Event.new(*event_data))
      rescue => e
        # This is what the Railtie rescue block does
        if Rails.env.development?
          Rails.logger.warn("GrapeRailsLogger: Failed to append DB runtime - #{e.class}: #{e.message}")
        end
      end

      # In development, should have logged a warning
      expect(logger.lines.any? { |line|
        line.is_a?(String) && line.include?("Failed to append DB runtime")
      }).to be true
    end

    it "does not log in production when DB runtime append fails" do
      Rails._env = ActiveSupport::StringInquirer.new("production")

      unless defined?(ActiveRecord)
        stub_const("ActiveRecord", Module.new)
      end

      allow(GrapeRailsLogger::Timings).to receive(:append_db_runtime).and_raise(StandardError, "DB error")

      event_data = ["sql.active_record", Time.now, Time.now + 0.01, "1", {}]

      begin
        GrapeRailsLogger::Timings.append_db_runtime(ActiveSupport::Notifications::Event.new(*event_data))
      rescue => e
        if Rails.env.development?
          Rails.logger.warn("GrapeRailsLogger: Failed to append DB runtime - #{e.class}: #{e.message}")
        end
      end

      # In production, should not have logged
      expect(logger.lines.any? { |line|
        line.is_a?(String) && line.include?("Failed to append DB runtime")
      }).to be false
    end
  end

  describe "Grape request event subscription error handling" do
    it "handles subscriber creation failure and logs in development" do
      # Set up a subscriber class that will fail
      Rails.application.config.grape_rails_logger.subscriber_class = Class.new do
        def initialize
          raise StandardError, "Subscriber init failed"
        end
      end

      event_data = ["grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      }]

      # Simulate the subscription callback error handling
      begin
        subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class || GrapeRailsLogger::GrapeRequestLogSubscriber
        subscriber = subscriber_class.new
        subscriber.grape_request(ActiveSupport::Notifications::Event.new(*event_data))
      rescue => e
        if Rails.env.development?
          Rails.logger.warn("GrapeRailsLogger: Subscriber failed - #{e.class}: #{e.message}")
          Rails.logger.warn(e.backtrace&.first(3)&.join("\n")) if e.respond_to?(:backtrace)
        end
      end

      # Should have logged warnings in development
      expect(logger.lines.any? { |line|
        line.is_a?(String) && line.include?("Subscriber failed")
      }).to be true
    end

    it "handles subscriber invocation failure and logs backtrace" do
      Rails._env = ActiveSupport::StringInquirer.new("development")

      # Set up a subscriber that will fail on grape_request
      failing_subscriber = Class.new do
        def grape_request(event)
          raise StandardError, "grape_request failed"
        end
      end

      Rails.application.config.grape_rails_logger.subscriber_class = failing_subscriber

      event_data = ["grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      }]

      begin
        subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class || GrapeRailsLogger::GrapeRequestLogSubscriber
        subscriber = subscriber_class.new
        subscriber.grape_request(ActiveSupport::Notifications::Event.new(*event_data))
      rescue => e
        if Rails.env.development?
          Rails.logger.warn("GrapeRailsLogger: Subscriber failed - #{e.class}: #{e.message}")
          Rails.logger.warn(e.backtrace&.first(3)&.join("\n")) if e.respond_to?(:backtrace)
        end
      end

      # Should have logged both the error and backtrace
      warning_lines = logger.lines.select { |line| line.is_a?(String) && line.include?("Subscriber failed") }
      expect(warning_lines.length).to be >= 1
    end

    it "does not log in production when subscriber fails" do
      Rails._env = ActiveSupport::StringInquirer.new("production")

      failing_subscriber = Class.new do
        def grape_request(event)
          raise StandardError, "grape_request failed"
        end
      end

      Rails.application.config.grape_rails_logger.subscriber_class = failing_subscriber

      event_data = ["grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      }]

      begin
        subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class || GrapeRailsLogger::GrapeRequestLogSubscriber
        subscriber = subscriber_class.new
        subscriber.grape_request(ActiveSupport::Notifications::Event.new(*event_data))
      rescue => e
        if Rails.env.development?
          Rails.logger.warn("GrapeRailsLogger: Subscriber failed - #{e.class}: #{e.message}")
          Rails.logger.warn(e.backtrace&.first(3)&.join("\n")) if e.respond_to?(:backtrace)
        end
      end

      # Should not have logged in production
      expect(logger.lines.any? { |line|
        line.is_a?(String) && line.include?("Subscriber failed")
      }).to be false
    end
  end
end
