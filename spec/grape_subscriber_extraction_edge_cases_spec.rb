require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "GrapeRequestLogSubscriber extraction edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  describe "extract_controller" do
    it "returns nil when endpoint has no source" do
      endpoint = double("Endpoint", source: nil)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_controller, event)
      expect(result).to be_nil
    end

    it "returns nil when source has no source_location" do
      source = double("Source", source_location: nil)
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_controller, event)
      expect(result).to be_nil
    end

    it "returns nil when file_path is nil" do
      source = double("Source", source_location: [nil, 10])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_controller, event)
      expect(result).to be_nil
    end

    it "returns nil when Rails.root is nil" do
      source = double("Source", source_location: ["/some/path/app/api/users.rb", 10])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      allow(Rails).to receive(:root).and_return(nil)

      result = subscriber.send(:extract_controller, event)
      expect(result).to be_nil
    end

    it "uses fallback camelization when ActiveSupport::Inflector is not defined" do
      source = double("Source", source_location: [File.join(Rails.root.to_s, "app/api/users/profile.rb"), 10])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      # Temporarily hide ActiveSupport::Inflector if it exists
      original_inflector = ActiveSupport.const_get(:Inflector) if defined?(ActiveSupport::Inflector)
      if defined?(ActiveSupport::Inflector)
        ActiveSupport.send(:remove_const, :Inflector) if ActiveSupport.const_defined?(:Inflector)
      end

      begin
        result = subscriber.send(:extract_controller, event)
        expect(result).to eq("Users::Profile")
      ensure
        # Restore
        if original_inflector && !defined?(ActiveSupport::Inflector)
          ActiveSupport.const_set(:Inflector, original_inflector)
        end
      end
    end

    it "handles errors gracefully and returns nil" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:source).and_raise(StandardError, "Source failed")
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_controller, event)
      expect(result).to be_nil
    end

    it "handles file path not in Rails root" do
      source = double("Source", source_location: ["/outside/path/file.rb", 10])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_controller, event)
      # Should still process it, just won't strip Rails root
      expect(result).to be_a(String)
    end
  end

  describe "extract_source_location" do
    it "returns nil when endpoint has no source" do
      endpoint = double("Endpoint", source: nil)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_source_location, event)
      expect(result).to be_nil
    end

    it "returns nil when source_location is nil" do
      source = double("Source", source_location: nil)
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_source_location, event)
      expect(result).to be_nil
    end

    it "returns nil when loc is nil" do
      source = double("Source", source_location: [nil, 10])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_source_location, event)
      expect(result).to be_nil
    end

    it "does not strip Rails root when path doesn't start with it" do
      source = double("Source", source_location: ["/outside/path/file.rb", 15])
      endpoint = double("Endpoint", source: source)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_source_location, event)
      expect(result).to eq("/outside/path/file.rb:15")
    end

    it "handles errors gracefully and returns nil" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:source).and_raise(StandardError, "Source failed")
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_source_location, event)
      expect(result).to be_nil
    end
  end

  describe "safe_rails_root" do
    it "returns nil when Rails is not defined" do
      original_rails = Object.const_get(:Rails) if defined?(Rails)
      if defined?(Rails)
        Object.send(:remove_const, :Rails)
      end

      begin
        result = subscriber.send(:safe_rails_root)
        expect(result).to be_nil
      ensure
        if original_rails && !defined?(Rails)
          Object.const_set(:Rails, original_rails)
        end
      end
    end

    it "returns nil when Rails doesn't respond to root" do
      allow(Rails).to receive(:respond_to?).with(:root).and_return(false)

      result = subscriber.send(:safe_rails_root)
      expect(result).to be_nil
    end

    it "returns nil when Rails.root is nil" do
      allow(Rails).to receive(:root).and_return(nil)

      result = subscriber.send(:safe_rails_root)
      expect(result).to be_nil
    end

    it "handles errors gracefully and returns nil" do
      allow(Rails).to receive(:root).and_raise(StandardError, "Root failed")

      result = subscriber.send(:safe_rails_root)
      expect(result).to be_nil
    end

    it "converts Pathname to string" do
      pathname = Pathname.new("/tmp/test")
      allow(Rails).to receive(:root).and_return(pathname)

      result = subscriber.send(:safe_rails_root)
      expect(result).to eq("/tmp/test")
      expect(result).to be_a(String)
    end
  end

  describe "extract_params" do
    it "returns empty hash when request is nil" do
      result = subscriber.send(:extract_params, nil)
      expect(result).to eq({})
    end

    it "returns empty hash when request.params is nil" do
      request = double("Request", params: nil, env: {})
      result = subscriber.send(:extract_params, request)
      expect(result).to eq({})
    end

    it "excludes route_info symbol key" do
      params_obj = double("Params")
      allow(params_obj).to receive(:to_unsafe_h).and_return({user: "bob", route_info: {}})
      allow(params_obj).to receive(:empty?).and_return(false)
      allow(params_obj).to receive(:respond_to?).with(:to_unsafe_h).and_return(true)

      request = double("Request", params: params_obj, env: {})
      result = subscriber.send(:extract_params, request)

      expect(result).not_to have_key(:route_info)
      expect(result).not_to have_key("route_info")
    end

    it "handles extraction errors gracefully" do
      request = double("Request")
      allow(request).to receive(:params).and_raise(StandardError, "Params failed")
      allow(request).to receive(:env).and_return({})

      result = subscriber.send(:extract_params, request)
      expect(result).to eq({})
    end
  end

  describe "extract_format" do
    it "uses ActionDispatch::Request format when available" do
      if defined?(ActionDispatch::Request)
        request = double("Request", env: {"api.format" => ".json"})
        rails_request = double("RailsRequest", format: double("Format", to_sym: :xml))
        allow(ActionDispatch::Request).to receive(:new).and_return(rails_request)

        result = subscriber.send(:extract_format, request)
        expect(result).to eq("xml")
      end
    end

    it "falls back to Grape format when ActionDispatch fails" do
      request = double("Request", format: ".json", env: {})
      allow(request).to receive(:try).with(:format).and_return(".json")

      result = subscriber.send(:extract_format, request)
      expect(result).to eq("json")
    end

    it "uses env api.format when request.format is nil" do
      request = double("Request", format: nil, env: {"api.format" => ".xml"})
      allow(request).to receive(:try).with(:format).and_return(nil)

      result = subscriber.send(:extract_format, request)
      expect(result).to eq("xml")
    end

    it "uses env rack.request.formats when api.format is nil" do
      request = double("Request", format: nil, env: {"rack.request.formats" => [".json"]})
      allow(request).to receive(:try).with(:format).and_return(nil)

      result = subscriber.send(:extract_format, request)
      expect(result).to eq("json")
    end

    it "defaults to json when all sources fail" do
      request = double("Request", format: nil, env: {})
      allow(request).to receive(:try).with(:format).and_return(nil)

      result = subscriber.send(:extract_format, request)
      expect(result).to eq("json")
    end

    it "handles ActionDispatch::Request creation failure" do
      if defined?(ActionDispatch::Request)
        request = double("Request", env: {})
        allow(ActionDispatch::Request).to receive(:new).and_raise(StandardError, "Request creation failed")
        allow(request).to receive(:try).with(:format).and_return(nil)

        result = subscriber.send(:extract_format, request)
        # Should fall through to Grape format detection
        expect(result).to eq("json")
      end
    end
  end

  describe "extract_action" do
    it "returns unknown when endpoint is nil" do
      env = {}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("unknown")
    end

    it "returns unknown when endpoint.options is nil" do
      endpoint = double("Endpoint", options: nil)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("unknown")
    end

    it "returns unknown when method is nil" do
      endpoint = double("Endpoint", options: {method: nil, path: ["/users"]})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("unknown")
    end

    it "returns unknown when path is nil" do
      endpoint = double("Endpoint", options: {method: ["GET"], path: nil})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("unknown")
    end

    it "returns method downcase for root path" do
      endpoint = double("Endpoint", options: {method: ["POST"], path: ["/"]})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("post")
    end

    it "returns method downcase for empty path" do
      endpoint = double("Endpoint", options: {method: ["DELETE"], path: [""]})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("delete")
    end

    it "handles path with colons and slashes" do
      endpoint = double("Endpoint", options: {method: ["PUT"], path: ["/api/users/:id/update"]})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      result = subscriber.send(:extract_action, event)
      expect(result).to eq("put_api_users_id_update")
    end
  end
end
