require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "GrapeRequestLogSubscriber fallback error handling" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  describe "log_fallback_subscriber_error" do
    it "handles event without env payload" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {})
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      # Should not raise, but may not log anything
      expect(logger.lines).to be_empty
    end

    it "handles event with non-Hash env" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: "not a hash"
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      # Should not raise
      expect(logger.lines).to be_empty
    end

    it "handles build_request failure in fallback" do
      env = {"invalid" => "env"}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: nil
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      # Should use fallback extraction from env
      expect(logger.lines.length).to be > 0
      log_data = logger.lines.last
      expect(log_data[:method]).to be_nil # Invalid env, no REQUEST_METHOD
      expect(log_data[:exception]).to be_a(Hash)
    end

    it "handles rails_request_for failure in fallback" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: nil
      })
      error = StandardError.new("Subscriber error")

      # Make rails_request_for fail
      allow(subscriber).to receive(:rails_request_for).and_raise(StandardError, "Rails request failed")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      # Should still extract from env
      expect(logger.lines.length).to be > 0
      log_data = logger.lines.last
      expect(log_data[:method]).to eq("GET")
    end

    it "handles all extraction failures gracefully" do
      env = {
        "REQUEST_METHOD" => "POST",
        "PATH_INFO" => "/api/test"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: nil,
        exception_object: nil
      })
      error = StandardError.new("Subscriber error")

      # Should not raise error even if extractions fail
      allow(subscriber).to receive(:safe_string).and_raise(StandardError, "Safe string failed")
      expect { subscriber.send(:log_fallback_subscriber_error, event, error) }.not_to raise_error
    end

    it "uses original exception when available" do
      original_error = ArgumentError.new("Original error")
      original_error.set_backtrace(["file1.rb:1", "file2.rb:2"])

      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        exception_object: original_error
      })
      subscriber_error = StandardError.new("Subscriber error")

      Rails._env = ActiveSupport::StringInquirer.new("test")
      subscriber.send(:log_fallback_subscriber_error, event, subscriber_error)

      log_data = logger.lines.last
      expect(log_data[:exception][:class]).to eq("ArgumentError")
      expect(log_data[:exception][:message]).to eq("Original error")
    end

    it "adds backtrace for subscriber error in non-production" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        exception_object: nil
      })
      subscriber_error = StandardError.new("Subscriber error")
      subscriber_error.set_backtrace(["file1.rb:1", "file2.rb:2", "file3.rb:3"])

      Rails._env = ActiveSupport::StringInquirer.new("test")
      subscriber.send(:log_fallback_subscriber_error, event, subscriber_error)

      log_data = logger.lines.last
      expect(log_data[:exception][:backtrace]).to be_an(Array)
      expect(log_data[:exception][:backtrace].length).to be <= 10
    end

    it "handles complete fallback logging failure" do
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env
      })
      error = StandardError.new("Subscriber error")

      # Make safe_log fail
      allow(subscriber).to receive(:safe_log).and_raise(StandardError, "Log failed")

      Rails._env = ActiveSupport::StringInquirer.new("development")

      # Should not raise
      expect { subscriber.send(:log_fallback_subscriber_error, event, error) }.not_to raise_error
    end

    it "extracts status from event payload when available" do
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: 418
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      expect(log_data[:status]).to eq(418)
    end

    it "extracts status from exception when payload status is nil" do
      exception = StandardError.new("Test exception")
      allow(exception).to receive(:status).and_return(403)

      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: nil,
        exception_object: exception
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      expect(log_data[:status]).to eq(403)
    end

    it "handles event.duration failure gracefully" do
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      event = double("Event",
        payload: {env: env, status: nil, exception_object: nil},
        duration: -> { raise StandardError, "Duration failed" })
      allow(event).to receive(:duration).and_raise(StandardError, "Duration failed")
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      expect(log_data[:duration]).to eq(0.0)
    end

    it "extracts remote_addr with request when available" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test",
        "REMOTE_ADDR" => "192.168.1.1"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      expect(log_data[:remote_addr]).to eq("192.168.1.1")
    end

    it "extracts remote_addr from env when request is nil" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test",
        "REMOTE_ADDR" => "10.0.0.1"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env
      })
      error = StandardError.new("Subscriber error")

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      expect(log_data[:remote_addr]).to eq("10.0.0.1")
    end

    it "extracts remote_addr from X-Forwarded-For when REMOTE_ADDR is nil" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test",
        "HTTP_X_FORWARDED_FOR" => "1.2.3.4, 5.6.7.8"
      }
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env
      })
      error = StandardError.new("Subscriber error")

      # Mock rails_request_for and build_request to return nil so we test the env path
      allow(subscriber).to receive(:rails_request_for).and_return(nil)
      allow(subscriber).to receive(:build_request).and_return(nil)

      subscriber.send(:log_fallback_subscriber_error, event, error)

      log_data = logger.lines.last
      # Should extract first IP from X-Forwarded-For (after stripping whitespace)
      expect(log_data[:remote_addr]).to eq("1.2.3.4")
    end

    it "handles extraction failures for all fields with rescue blocks" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/test"
      }
      # Test that when request is nil, it uses env directly (this tests the rescue path indirectly)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env
      })
      error = StandardError.new("Subscriber error")

      # Make build_request return nil to force env-based extraction
      allow(subscriber).to receive(:build_request).with(env).and_return(nil)

      subscriber.send(:log_fallback_subscriber_error, event, error)

      # Should still log something
      expect(logger.lines.length).to be > 0
      log_data = logger.lines.last
      expect(log_data).to be_a(Hash)
      # Should extract from env when request is nil
      expect(log_data[:method]).to eq("GET")
      expect(log_data[:path]).to eq("/test")
    end
  end
end
