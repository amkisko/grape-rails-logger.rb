# grape-rails-logger

[![Gem Version](https://badge.fury.io/rb/grape-rails-logger.svg?v=)](https://badge.fury.io/rb/grape-rails-logger) [![Test Status](https://github.com/amkisko/grape-rails-logger.rb/actions/workflows/ci.yml/badge.svg)](https://github.com/amkisko/grape-rails-logger.rb/actions/workflows/ci.yml) [![codecov](https://codecov.io/gh/amkisko/grape-rails-logger.rb/graph/badge.svg?token=)](https://codecov.io/gh/amkisko/grape-rails-logger.rb)

Unified, Rails-compatible JSON request logging for Grape APIs with ActiveRecord timing, parameter filtering, and structured context.

This gem wires Grape request lifecycle to `ActiveSupport::Notifications` and logs via `Rails.logger` in a structured way. It works standalone or seamlessly integrates with `activesupport-json_logging` for JSON-formatted output.

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>

## Installation

Add to your Gemfile:

```ruby
gem "grape-rails-logger"
```

Run bundler:

```bash
bundle install
```

Add middleware into your Grape API:

```ruby
class API < Grape::API
  use GrapeRailsLogger::GrapeInstrumentation
  # optionally for local tracing
  # use GrapeRailsLogger::DebugTracer
end
```

## What you get

- Automatic request instrumentation via `GrapeInstrumentation` middleware
- Structured logging with request metadata (method, path, status, duration, DB timings)
- Controller and action extraction from Grape endpoint source locations
- Source location tracking (file:line) for debugging
- ActiveRecord SQL timing aggregation per request via `sql.active_record` notifications
- Automatic parameter filtering using Rails `ParameterFilter` with manual fallback
- Exception logging with class, message, and backtrace for unhandled errors
- Optional `DebugTracer` middleware for detailed request tracing (when `TRACE` env var is set)
- Works standalone (outputs structured hashes) or with `activesupport-json_logging` (outputs JSON)

### Standalone usage

The gem works out of the box with any Rails logger. It logs structured Hash data:

```ruby
# Works with default Rails logger
class API < Grape::API
  use GrapeRailsLogger::GrapeInstrumentation
end
```

Log output will be a structured hash with fields like:
- `method`, `path`, `status`, `duration`, `db`, `db_calls`
- `controller`, `action`, `source_location`
- `host`, `remote_addr`, `request_id`
- `params` (filtered)
- `exception` (when errors occur)

### With activesupport-json_logging (optional)

For JSON-formatted output, configure `activesupport-json_logging`:

```ruby
# config/initializers/json_logging.rb
Rails.application.configure do
  base_logger = ActiveSupport::Logger.new($stdout)
  config.logger = JsonLogging.new(base_logger)
end
```

The gem detects and works seamlessly with JsonLogging-wrapped loggers - no additional configuration needed. Log entries will be formatted as JSON automatically.

## What gets logged

Each request logs a structured entry with:

- **Request metadata**: `method`, `path`, `status`, `duration`, `host`, `remote_addr`, `request_id`
- **Route information**: `controller` (extracted from API source file), `action` (inferred from route), `source_location` (file:line)
- **Performance metrics**: `duration` (total request time in ms), `db` (ActiveRecord query time in ms), `db_calls` (SQL query count)
- **Parameters**: `params` (automatically filtered using Rails `filter_parameters`)
- **Exceptions**: `exception` object with `class`, `message`, and `backtrace` (non-production only) for unhandled errors

## ActiveRecord timings

DB timing is automatically captured via `sql.active_record` notifications and aggregated per request. The timing is thread-safe using `IsolatedExecutionState` (Rails 7.1+) or `Thread.current` (Rails 6-7.0).

## Parameter filtering

The gem automatically uses Rails' `config.filter_parameters` when available. Configure it in `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]
```

When Rails `ParameterFilter` is not available, the gem falls back to manual filtering that detects sensitive patterns (password, secret, token, key) in parameter keys.

## Exception logging

Unhandled exceptions are automatically logged with:
- Exception class name
- Exception message
- Short backtrace (first 10 lines, non-production only)
- HTTP status code extracted from the exception

Grape's `error!` method and custom exceptions with `status` method or `@status` instance variable are automatically detected.

## Debug tracing

Optional `DebugTracer` middleware provides detailed request tracing when the `debug` gem is installed:

```ruby
class API < Grape::API
  use GrapeRailsLogger::GrapeInstrumentation
  use GrapeRailsLogger::DebugTracer  # Only traces when TRACE=1
end
```

Enable tracing by setting the `TRACE` environment variable:

```bash
TRACE=1 rails server
```

The middleware gracefully degrades if the `debug` gem is not installed.

## Compatibility

- Rails 6.0, 6.1, 7.0, 7.1, 7.2, 8.0+
- Grape >= 1.6
- Ruby >= 2.7
- TruffleRuby support (tested with Rails 8)

**Note:** In Rails 7.1+, the gem uses `ActiveSupport::IsolatedExecutionState` for improved thread/Fiber safety. In Rails 6-7.0, it falls back to `Thread.current`.

## Development

```bash
# Install dependencies
bundle install
bundle exec appraisal install

# Run tests for current Rails version
bundle exec rspec

# Run tests for all Rails versions
bin/appraisals

# Run tests for specific Rails version
bin/appraisals rails-7.0

# Run tests for multiple versions
bin/appraisals rails-7.0 rails-8.0

# Or use appraisal directly
bundle exec appraisal rails-7.0 rspec

bundle exec standardrb --fix
```

### Development: Using from Local Repository

When developing the gem or testing changes in your application, you can point your Gemfile to a local path:

```ruby
# In your application's Gemfile
gem "grape-rails-logger", path: "../grape-rails-logger.rb", require: "grape_rails_logger"
```

Then run:

```bash
bundle install
```

**Note:** When using `path:` in your Gemfile, Bundler will use the local gem directly. Changes you make to the gem code will be immediately available in your application without needing to rebuild or reinstall the gem. This is ideal for development and testing.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amkisko/grape-rails-logger.rb

Contribution policy:
- New features are not necessarily added to the gem
- Pull request should have test coverage for affected parts
- Pull request should have changelog entry

Review policy:
- It might take up to 2 calendar weeks to review and merge critical fixes
- It might take up to 6 calendar months to review and merge pull request
- It might take up to 1 calendar year to review an issue

## Publishing

```sh
rm grape-rails-logger-*.gem
gem build grape-rails-logger.gemspec
gem push grape-rails-logger-*.gem
```

Or use the release script:

```sh
usr/bin/release.sh
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
