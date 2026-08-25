# Migrating Retriable

Upgrade guides for Retriable's breaking changes, newest first. See the
[CHANGELOG](../CHANGELOG.md) for the full history of every release.

- [4.x to 5.x](#4x-to-5x)
- [3.x to 4.0](#3x-to-40)

## 4.x to 5.x

Retriable 5.0 makes configuration copy-on-write so that concurrent readers see
one complete configuration. As part of that change, `Retriable.config` returns a
deeply frozen snapshot. Code that mutates this snapshot directly now raises
`FrozenError`:

```ruby
Retriable.config.sleep_disabled = true # => FrozenError
Retriable.config.contexts[:api] = {}   # => FrozenError
```

Move these writes into a `Retriable.configure` block:

```ruby
Retriable.configure do |config|
  config.sleep_disabled = true
  config.contexts[:api] = {}
end
```

Check test setup files such as `spec_helper` and `rails_helper`, where direct
configuration writes are common. Reading `Retriable.config` is unchanged.

## 3.x to 4.0

### Ruby version

Retriable 4.0 requires Ruby 3.2 or later. If your application still runs Ruby
2.3.0 through 3.1.x, pin Retriable to the 3.8 release line in your Gemfile:

```ruby
gem "retriable", "~> 3.8"
```

### `timeout:` option removed

Retriable 4.0 removes the `timeout:` option deprecated in 3.8.0. The option
called `Timeout.timeout`, which can interrupt code at any line and leave
non-interrupt-safe libraries in a corrupt state. [Issue #96](https://github.com/kamui/retriable/issues/96)
has the original bug report.

Replace code such as `Retriable.retriable(timeout: 5) { ... }` with one of the
following approaches.

1. Prefer the library's own timeout setting, such as `Net::HTTP#read_timeout`,
   Faraday's `request.timeout`, or a database statement timeout. These settings
   avoid the arbitrary interruption caused by `Timeout.timeout`.

2. If the library has no timeout setting, wrap the operation yourself:

   ```ruby
   require "timeout"

   Retriable.retriable do
     Timeout.timeout(5) do
       # code here...
     end
   end
   ```

   This keeps the old behavior, including its risks. `Timeout.timeout` may
   interrupt code while it holds a mutex, file handle, network socket, or other
   internal state. Use it only when the library offers no safer timeout. For more
   detail, read [why Ruby's `Timeout` is dangerous](https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/),
   [Headius on `Thread#raise` and `Timeout`](http://blog.headius.com/2008/02/ruby-threadraise-threadkill-timeoutrb.html),
   [In Ruby, don't use `Timeout`](https://adamhooper.medium.com/in-ruby-dont-use-timeout-77d9d4e5a001), or
   [Timeout: Ruby's most dangerous API](https://www.mikeperham.com/2015/05/08/timeout-rubys-most-dangerous-api/).

   `Timeout.timeout(5)` applies to each attempt, so every retry gets a new
   five-second limit. Use `max_elapsed_time:` to cap the total time spent across
   all attempts.

Passing `timeout:` to `Retriable.retriable` or `Retriable.with_override` now
raises `ArgumentError`. Setting `timeout` in `Retriable.configure` now raises
`NoMethodError` because the configuration attribute no longer exists.
