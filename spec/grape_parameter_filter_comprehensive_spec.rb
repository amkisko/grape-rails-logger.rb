require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "Parameter filtering" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  describe "filter_params" do
    it "uses Rails ParameterFilter when configured" do
      Rails.application.config.filter_parameters = [:password, :secret]
      params = {password: "secret", username: "bob", secret: "key"}

      filtered = subscriber.send(:filter_params, params)
      expect(filtered[:password]).to eq("[FILTERED]")
      expect(filtered[:secret]).to eq("[FILTERED]")
      expect(filtered[:username]).to eq("bob")
    end

    it "falls back to manual filtering when Rails filter unavailable" do
      # Test nil, empty array, and missing respond_to?
      [nil, []].each do |value|
        Rails.application.config.filter_parameters = value
        filtered = subscriber.send(:filter_params, {password: "secret"})
        expect(filtered[:password]).to eq("[FILTERED]")
      end

      allow(Rails.application.config).to receive(:respond_to?).with(:filter_parameters).and_return(false)
      filtered = subscriber.send(:filter_params, {password: "secret"})
      expect(filtered[:password]).to eq("[FILTERED]")
    end

    it "falls back to manual filtering when Rails filter fails" do
      filter_mock = double("Filter")
      allow(filter_mock).to receive(:filter).and_raise(StandardError, "Filter failed")
      allow(subscriber).to receive(:rails_parameter_filter).and_return(filter_mock)

      filtered = subscriber.send(:filter_params, {password: "secret", username: "bob"})
      expect(filtered[:password]).to eq("[FILTERED]")
      expect(filtered[:username]).to eq("bob")
    end

    it "handles edge cases gracefully" do
      # Non-hash filter result - should return empty hash (not fall back to manual)
      # The code checks cleaned.is_a?(Hash) and returns {} if not
      filter_instance = double("Filter")
      allow(filter_instance).to receive(:filter).and_return("not a hash")
      allow(subscriber).to receive(:rails_parameter_filter).and_return(filter_instance)
      # When filter returns non-hash, it returns {}
      filtered = subscriber.send(:filter_params, {password: "secret", user: "bob"})
      expect(filtered).to eq({})

      # Filter throws exception - should fall back to manual filtering
      filter_instance = double("Filter")
      allow(filter_instance).to receive(:filter).and_raise(StandardError, "Filter failed")
      allow(subscriber).to receive(:rails_parameter_filter).and_return(filter_instance)
      # When filter throws, it falls back to manual filtering in rescue
      filtered = subscriber.send(:filter_params, {password: "secret", user: "bob"})
      # Manual filtering should filter password keys
      expect(filtered[:password]).to eq("[FILTERED]")
      expect(filtered[:user]).to eq("bob")

      # Filter initialization failure - ensure config exists first
      Rails.application.config.filter_parameters = [:password]
      allow(Rails.application.config).to receive(:filter_parameters).and_raise(StandardError, "Config failed")
      # rails_parameter_filter will catch the exception and return nil, then manual filtering is used
      filtered = subscriber.send(:filter_params, {password: "secret", user: "bob"})
      # Manual filtering should filter password keys - check that password is filtered
      expect(filtered[:password]).to eq("[FILTERED]")
      expect(filtered[:user]).to eq("bob")

      # Non-hash params
      expect(subscriber.send(:filter_params, "not a hash")).to eq({})
      expect(subscriber.send(:filter_params, nil)).to eq({})
    end

    it "excludes PARAM_EXCEPTIONS from final result" do
      params = {controller: "users", action: "index", format: "json", username: "bob"}
      filtered = subscriber.send(:filter_params, params)
      expect(filtered).not_to have_key(:controller)
      expect(filtered).not_to have_key(:action)
      expect(filtered).not_to have_key(:format)
      expect(filtered[:username]).to eq("bob")
    end
  end

  describe "rails_parameter_filter" do
    it "returns filter when configured" do
      Rails.application.config.filter_parameters = [:password]
      filter = subscriber.send(:rails_parameter_filter)
      expect(filter).to respond_to(:filter)
      expect(filter).to be_a(ActiveSupport::ParameterFilter) if defined?(ActiveSupport::ParameterFilter)
    end

    it "returns nil when filter_parameters unavailable" do
      allow(Rails.application.config).to receive(:respond_to?).with(:filter_parameters).and_return(false)
      expect(subscriber.send(:rails_parameter_filter)).to be_nil
    end

    it "handles filter creation failure" do
      Rails.application.config.filter_parameters = [:password]
      allow(ActiveSupport::ParameterFilter).to receive(:new).and_raise(StandardError, "Filter creation failed")
      expect(subscriber.send(:rails_parameter_filter)).to be_nil
    end
  end

  describe "filter_parameters_manually" do
    it "filters nested hashes and arrays recursively" do
      params = {
        user: {name: "John", password: "secret123", profile: {email: "john@example.com", api_key: "key123"}},
        users: [{name: "Alice", password: "pass1"}, {name: "Bob", secret: "sec1"}]
      }
      result = subscriber.send(:filter_parameters_manually, params)
      expect(result[:user][:password]).to eq("[FILTERED]")
      expect(result[:user][:profile][:api_key]).to eq("[FILTERED]")
      expect(result[:users][0][:password]).to eq("[FILTERED]")
      expect(result[:users][1][:secret]).to eq("[FILTERED]")
      expect(result[:user][:name]).to eq("John")
    end

    it "filters values containing sensitive substrings" do
      expect(subscriber.send(:filter_value, "contains password here")).to eq("[FILTERED]")
      expect(subscriber.send(:filter_value, "my_secret_key")).to eq("[FILTERED]")
      expect(subscriber.send(:filter_value, "auth_token_123")).to eq("[FILTERED]")
      expect(subscriber.send(:filter_value, "api_key_value")).to eq("[FILTERED]")
      expect(subscriber.send(:filter_value, "username")).to eq("username")
    end

    it "filters keys containing sensitive substrings" do
      expect(subscriber.send(:should_filter_key?, "user_password")).to be true
      expect(subscriber.send(:should_filter_key?, "api_secret")).to be true
      expect(subscriber.send(:should_filter_key?, "access_token")).to be true
      expect(subscriber.send(:should_filter_key?, "private_key")).to be true
      expect(subscriber.send(:should_filter_key?, "username")).to be false
    end

    it "respects limits and handles edge cases" do
      # Depth limit (depth > 10 returns marker)
      deep_params = {}
      current = deep_params
      15.times { |i|
        current["level#{i}"] = {}
        current = current["level#{i}"]
      }
      result = subscriber.send(:filter_parameters_manually, deep_params, 0)
      # At depth 11 (level10 -> level11), we hit the limit
      nested_result = result["level0"]
      10.times { |i| nested_result = nested_result["level#{i + 1}"] }
      expect(nested_result).to have_key("[FILTERED]")
      expect(nested_result["[FILTERED]"]).to eq("[max_depth_exceeded]")

      # Hash size limit
      large_params = {}
      60.times { |i| large_params["key#{i}"] = "value#{i}" }
      expect(subscriber.send(:filter_parameters_manually, large_params).size).to be <= 50

      # Array truncation
      params = {"items" => (1..150).to_a}
      expect(subscriber.send(:filter_parameters_manually, params)["items"].size).to eq(100)
    end

    it "handles non-string values" do
      expect(subscriber.send(:filter_value, 123)).to eq(123)
      expect(subscriber.send(:filter_value, true)).to eq(true)
      expect(subscriber.send(:filter_value, nil)).to be_nil
      expect(subscriber.send(:filter_value, [:array])).to eq([:array])
    end
  end
end
