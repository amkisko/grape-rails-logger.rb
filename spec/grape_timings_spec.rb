require "spec_helper"

RSpec.describe GrapeRailsLogger::Timings do
  describe ".reset_db_runtime" do
    it "resets both runtime and calls" do
      described_class.append_db_runtime(ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.1, "1", {}))
      expect(described_class.db_runtime).to be > 0
      expect(described_class.db_calls).to eq(1)

      described_class.reset_db_runtime
      expect(described_class.db_runtime).to eq(0)
      expect(described_class.db_calls).to eq(0)
    end
  end

  describe ".append_db_runtime" do
    it "accumulates duration and increments call count" do
      described_class.reset_db_runtime
      start = Time.now
      end1 = start + 0.05
      end2 = start + 0.03
      event1 = ActiveSupport::Notifications::Event.new("sql.active_record", start, end1, "1", {})
      event2 = ActiveSupport::Notifications::Event.new("sql.active_record", start, end2, "2", {})

      described_class.append_db_runtime(event1)
      runtime1 = described_class.db_runtime
      expect(runtime1).to be > 0
      expect(described_class.db_calls).to eq(1)

      described_class.append_db_runtime(event2)
      runtime2 = described_class.db_runtime
      expect(runtime2).to be > runtime1
      expect(described_class.db_calls).to eq(2)
    end
  end

  describe ".execution_state" do
    it "uses IsolatedExecutionState when available" do
      if defined?(ActiveSupport::IsolatedExecutionState)
        expect(described_class.execution_state).to eq(ActiveSupport::IsolatedExecutionState)
      else
        expect(described_class.execution_state).to eq(Thread.current)
      end
    end
  end
end
