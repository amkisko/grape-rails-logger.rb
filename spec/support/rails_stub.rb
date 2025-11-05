module Rails
  class << self
    attr_accessor :_logger, :_root, :_env, :_application
  end

  def self.root
    self._root ||= Pathname.new(Dir.pwd)
  end

  def self.env
    self._env ||= ActiveSupport::StringInquirer.new("test")
  end

  def self.logger
    _logger
  end

  def self.application
    self._application ||= begin
      config = Struct.new(:filter_parameters, :grape_rails_logger).new(
        [],
        ActiveSupport::OrderedOptions.new.tap do |opts|
          opts.enabled = true
          opts.subscriber_class = GrapeRailsLogger::GrapeRequestLogSubscriber
          opts.logger = nil # Will use Rails.logger
          opts.tag = "Grape"
        end
      )
      Struct.new(:config).new(config)
    end
  end
end
