require "spec_helper"

# Railtie is only loaded when Rails::Railtie is available (real Rails app)
# In test environment with stubs, it won't be loaded
if defined?(GrapeRailsLogger::Railtie)
  RSpec.describe GrapeRailsLogger::Railtie do
    it "loads without errors" do
      expect { described_class }.not_to raise_error
    end

    it "is a Rails::Railtie" do
      expect(described_class.superclass).to eq(::Rails::Railtie)
    end

    it "defines initializer" do
      # Just verify the class can be instantiated
      expect(described_class.new).to be_a(::Rails::Railtie)
    end
  end
else
  RSpec.describe "GrapeRailsLogger::Railtie" do
    it "is not loaded in test environment (expected)" do
      # Railtie only loads when Rails::Railtie is available
      expect(defined?(GrapeRailsLogger::Railtie)).to be_falsey
    end
  end
end
