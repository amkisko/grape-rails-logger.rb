require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "Controller and source location extraction" do
  let(:logger) { TestLogger.new }
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  before do
    Rails._logger = logger
    Rails._root = Pathname.new("/app")
  end

  describe "extract_controller" do
    it "extracts controller from source location" do
      endpoint = double("Endpoint")
      source = double("Source", source_location: ["/app/app/api/users.rb", 42])
      allow(endpoint).to receive(:source).and_return(source)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      controller = subscriber.send(:extract_controller, event)
      expect(controller).to eq("Users")
    end

    it "handles nil Rails.root" do
      original_root = Rails._root
      begin
        Rails._root = nil
        # Mock Rails.root to return nil
        allow(Rails).to receive(:root).and_return(nil)
        endpoint = double("Endpoint")
        source = double("Source", source_location: ["/app/app/api/users.rb", 42])
        allow(endpoint).to receive(:source).and_return(source)
        event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
          env: {"api.endpoint" => endpoint}
        })

        controller = subscriber.send(:extract_controller, event)
        expect(controller).to be_nil
      ensure
        Rails._root = original_root
        begin
          allow(Rails).to receive(:root).and_call_original
        rescue
          nil
        end
      end
    end

    it "handles missing endpoint" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {}
      })
      controller = subscriber.send(:extract_controller, event)
      expect(controller).to be_nil
    end

    it "handles source location extraction failure" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:source).and_raise(StandardError, "source failed")
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      controller = subscriber.send(:extract_controller, event)
      expect(controller).to be_nil
    end
  end

  describe "extract_source_location" do
    it "extracts source location with line number" do
      endpoint = double("Endpoint")
      source = double("Source", source_location: ["/app/app/api/users.rb", 42])
      allow(endpoint).to receive(:source).and_return(source)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      loc = subscriber.send(:extract_source_location, event)
      expect(loc).to eq("app/api/users.rb:42")
    end

    it "handles paths outside Rails root" do
      endpoint = double("Endpoint")
      source = double("Source", source_location: ["/outside/path.rb", 1])
      allow(endpoint).to receive(:source).and_return(source)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      loc = subscriber.send(:extract_source_location, event)
      expect(loc).to eq("/outside/path.rb:1")
    end

    it "handles missing source location" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {}
      })
      loc = subscriber.send(:extract_source_location, event)
      expect(loc).to be_nil
    end
  end
end
