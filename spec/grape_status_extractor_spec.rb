require "spec_helper"

RSpec.describe GrapeRailsLogger::StatusExtractor do
  describe ".extract_status_from_exception" do
    it "extracts from status method" do
      ex = Class.new(StandardError) { def status = 410 }.new
      expect(described_class.extract_status_from_exception(ex)).to eq(410)
    end

    it "extracts from @status instance variable" do
      ex = StandardError.new
      ex.instance_variable_set(:@status, 422)
      expect(described_class.extract_status_from_exception(ex)).to eq(422)
    end

    it "extracts from options hash" do
      ex = Class.new(StandardError) do
        attr_reader :options
        def initialize
          @options = {status: 400}
          super
        end
      end.new
      expect(described_class.extract_status_from_exception(ex)).to eq(400)
    end

    it "returns 500 for exception without status" do
      ex = StandardError.new("generic error")
      expect(described_class.extract_status_from_exception(ex)).to eq(500)
    end

    it "handles non-integer status values" do
      ex1 = Class.new(StandardError) { def status = "404" }.new
      ex2 = StandardError.new.tap { |e| e.instance_variable_set(:@status, "422") }
      ex3 = Class.new(StandardError) do
        attr_reader :options
        def initialize
          @options = {status: "400"}
          super
        end
      end.new

      expect(described_class.extract_status_from_exception(ex1)).to eq(500)
      expect(described_class.extract_status_from_exception(ex2)).to eq(500)
      expect(described_class.extract_status_from_exception(ex3)).to eq(500)
    end

    it "handles invalid options" do
      ex1 = Class.new(StandardError) do
        attr_reader :options
        def initialize
          @options = "not a hash"
          super
        end
      end.new
      ex2 = Class.new(StandardError) do
        attr_reader :options
        def initialize
          @options = {other: "value"}
          super
        end
      end.new

      expect(described_class.extract_status_from_exception(ex1)).to eq(500)
      expect(described_class.extract_status_from_exception(ex2)).to eq(500)
    end

    it "uses exception class name mapping when available" do
      map = described_class::EXCEPTION_STATUS_MAP
      expect(map["ActiveRecord::RecordNotFound"]).to eq(404)
      expect(map["ActiveRecord::RecordInvalid"]).to eq(422)
      expect(map).to be_a(Hash)
      expect(map.length).to be > 0
    end

    it "handles NameError when constantizing exception class" do
      exception = StandardError.new("Error")
      allow(exception).to receive(:class).and_return(double(name: "NonExistent::Exception"))
      expect(described_class.extract_status_from_exception(exception)).to eq(500)
    end
  end
end
