# CHANGELOG

## 1.1.0 (2025-11-05)

- Removed `GrapeInstrumentation` middleware - instrumentation now happens automatically via Railtie
- Refactored internal code into focused modules (Timings, StatusExtractor, Subscriber, EndpointPatch, EndpointWrapper)
- Improved test coverage for core modules

## 1.0.0 (2025-11-04)

Initial stable release.

- Automatic request logging for Grape API endpoints
- Structured logging with method, path, status, duration, and database timings
- Automatic parameter filtering for sensitive data (passwords, secrets, tokens)
- Exception logging with error details and backtraces
- Debug tracing mode for detailed request inspection (when TRACE env var is set)
- Automatic Rails integration with zero configuration
- Works standalone or integrates with activesupport-json_logging
- Supports Rails 6.0 through 8.0+
- Thread-safe DB timing using IsolatedExecutionState (Rails 7.1+) or Thread.current (Rails 6-7.0)
- Controller and action extraction from Grape endpoint source locations
- Source location tracking (file:line) for debugging
