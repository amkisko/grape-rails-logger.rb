class TestLogger
  attr_reader :lines

  def initialize
    @lines = []
  end

  def info(obj)
    @lines << obj
  end

  def error(obj)
    @lines << obj
  end

  def debug(obj)
    @lines << obj
  end

  def warn(obj)
    @lines << obj
  end

  # Tagged logging support (Rails TaggedLogging)
  def tagged(*tags)
    yield
  end

  # Helper method to find Hash entries in logs
  def hash_entries
    lines.select { |l| l.is_a?(Hash) }
  end

  def last_hash
    hash_entries.last
  end
end
