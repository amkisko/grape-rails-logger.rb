# grape_rails_logger

[![Gem Version](https://badge.fury.io/rb/grape_rails_logger.svg?v=1.1.0)](https://badge.fury.io/rb/grape_rails_logger) [![Test Status](https://github.com/amkisko/grape_rails_logger.rb/actions/workflows/test.yml/badge.svg)](https://github.com/amkisko/grape_rails_logger.rb/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/amkisko/grape_rails_logger.rb/graph/badge.svg?token=RC5T0Y2Z5A)](https://codecov.io/gh/amkisko/grape_rails_logger.rb)

Rails-compatible structured logging for Grape APIs with ActiveRecord timing, parameter filtering, and exception tracking.

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>

## Installation

Add to your Gemfile:

```ruby
gem "grape_rails_logger"
```

Run `bundle install` or `gem install grape_rails_logger`.

## Usage

The gem works automatically in Rails applications. No configuration needed. It automatically patches `Grape::Endpoint#build_stack` to instrument requests and subscribes to `grape.request` notifications, logging structured data via `Rails.logger`. Works with any Rails logger or integrates with `activesupport-json_logging` for JSON output.

## What gets logged

Each request logs structured data with:
- Request metadata: `method`, `path`, `status`, `duration`, `host`, `remote_addr`, `request_id`
- Route information: `controller`, `action`, `source_location` (file:line)
- Performance metrics: `duration` (ms), `db` (ActiveRecord query time in ms), `db_calls` (SQL query count)
- Parameters: `params` (automatically filtered using Rails `filter_parameters`)
- Exceptions: `exception` object with `class`, `message`, and `backtrace` (non-production only)

## Configuration

Configure parameter filtering in `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]
```

When Rails `ParameterFilter` is not available, the gem falls back to manual filtering that detects sensitive patterns (password, secret, token, key) in parameter keys.

## Debug tracing

Optional `DebugTracer` middleware provides detailed request tracing when the `debug` gem is installed and `TRACE` environment variable is set:

```ruby
class API < Grape::API
  use GrapeRailsLogger::DebugTracer
end
```

Enable tracing: `TRACE=1 rails server`. The middleware gracefully degrades if the `debug` gem is not installed.

## Compatibility

- Rails 6.0, 6.1, 7.0, 7.1, 7.2, 8.0+
- Grape >= 1.6
- Ruby >= 2.7

In Rails 7.1+, the gem uses `ActiveSupport::IsolatedExecutionState` for improved thread/Fiber safety. In Rails 6-7.0, it falls back to `Thread.current`.

## Development

```bash
bundle install
bundle exec appraisal generate
bundle exec rspec
bin/appraisals
bundle exec standardrb --fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amkisko/grape_rails_logger.rb

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
rm grape_rails_logger-*.gem
gem build grape_rails_logger.gemspec
gem push grape_rails_logger-*.gem
```

Or use the release script:

```sh
usr/bin/release.sh
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
