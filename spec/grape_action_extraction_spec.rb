require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "Action extraction edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  describe "extract_action" do
    it "handles endpoint without options" do
      endpoint = double("Endpoint", options: nil)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      action = subscriber.send(:extract_action, event)
      expect(action).to eq("unknown")
    end

    it "handles missing method in options" do
      endpoint = double("Endpoint", options: {path: ["/test"]})
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      action = subscriber.send(:extract_action, event)
      expect(action).to eq("unknown")
    end

    it "handles missing path in options" do
      endpoint = double("Endpoint", options: {method: [:GET]})
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      action = subscriber.send(:extract_action, event)
      expect(action).to eq("unknown")
    end

    it "handles path with route parameters" do
      endpoint = double("Endpoint", options: {method: [:GET], path: ["/users/:id/posts/:post_id"]})
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      action = subscriber.send(:extract_action, event)
      expect(action).to eq("get_users_id_posts_post_id")
    end

    it "handles empty path" do
      endpoint = double("Endpoint", options: {method: [:POST], path: [""]})
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"api.endpoint" => endpoint}
      })

      action = subscriber.send(:extract_action, event)
      expect(action.to_s).to eq("post")
    end
  end
end
