# Retriable

![Build Status](https://github.com/kamui/retriable/actions/workflows/main.yml/badge.svg)

Retriable is a simple DSL to retry failed code blocks with randomized [exponential backoff](http://en.wikipedia.org/wiki/Exponential_backoff) time intervals. This is especially useful when interacting external APIs, remote services, or file system calls.

## Table of Contents

- [Requirements](#requirements)
- [Migration from 3.x to 4.0](#migration-from-3x-to-40)
- [Installation](#installation)
- [Usage](#usage)
  - [Defaults](#defaults)
  - [Options](#options)
    - [Configuring Which Options to Retry With :on](#configuring-which-options-to-retry-with-on)
    - [Advanced Retry Matching With :retry_if](#advanced-retry-matching-with-retry_if)
  - [Configuration](#configuration)
  - [Override](#override)
  - [Example Usage](#example-usage)
  - [Custom Interval Array](#custom-interval-array)
  - [Unbounded Retries (Opt-in)](#unbounded-retries-opt-in)
  - [Turn off Exponential Backoff](#turn-off-exponential-backoff)
  - [Callbacks](#callbacks)
    - [Disabling a Configured Callback Per Call](#disabling-a-configured-callback-per-call)
  - [Ensure/Else](#ensureelse)
- [Contexts](#contexts)
- [Kernel Extension](#kernel-extension)
- [Testing](#testing)
- [Credits](#credits)
- [Development](#development)
  - [Running Specs](#running-specs)

## Requirements

Ruby 3.2+

If you need Ruby 2.3.0-3.1.x support, use the [3.8.x branch](https://github.com/kamui/retriable/tree/3.8.x) by specifying `~> 3.8` in your Gemfile.

If you need Ruby 2.0.0-2.2.x support, use the [3.1 branch](https://github.com/kamui/retriable/tree/3.1.x) by specifying `~3.1` in your Gemfile.

If you need Ruby 1.9.3 support, use the [2.x branch](https://github.com/kamui/retriable/tree/2.x) by specifying `~2.1` in your Gemfile.

If you need Ruby 1.8.x to 1.9.2 support, use the [1.x branch](https://github.com/kamui/retriable/tree/1.x) by specifying `~1.4` in your Gemfile.

## Migration from 3.x to 4.0

### Ruby version

Retriable 4.0 requires Ruby 3.2 or later. If you run Ruby 2.3.0-3.1.x, or want to stay on the 3.x gem line, use Retriable 3.8.x by specifying `~> 3.8` in your Gemfile.

### `timeout:` option removed

The `timeout:` option was deprecated in Retriable 3.8.0 and has been removed in Retriable 4.0. It was a thin wrapper around `Timeout.timeout`, which has well-documented safety issues: it interrupts execution at arbitrary lines and can corrupt internal state in libraries that are not interrupt-safe. See [issue #96](https://github.com/kamui/retriable/issues/96) for the original report of this problem.

If you previously used `Retriable.retriable(timeout: 5) { ... }`, you have two recommended alternatives:

1. **Use your library's native timeout** (preferred). For example, configure `Net::HTTP#read_timeout`, Faraday's `request.timeout`, or your database client's statement timeout. Library-native timeouts do not have the safety issues of `Timeout.timeout`.

2. **Manage the timeout yourself inside the block** if no native option exists:

   ```ruby
   require "timeout"

   Retriable.retriable do
     Timeout.timeout(5) do
       # code here...
     end
   end
   ```

   **Note:** This still uses `Timeout.timeout`, which has the same safety issues that motivated removing the option — interruption can happen at any line, including inside non-interrupt-safe library code (mutexes, file handles, network sockets, allocator state). Prefer option 1 wherever possible. For background, see [why Ruby's `Timeout` is dangerous](https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/), [Headius on Thread#raise and Timeout](http://blog.headius.com/2008/02/ruby-threadraise-threadkill-timeoutrb.html), [In Ruby, don't use `Timeout`](https://adamhooper.medium.com/in-ruby-dont-use-timeout-77d9d4e5a001), and [Timeout: Ruby's most dangerous API](https://www.mikeperham.com/2015/05/08/timeout-rubys-most-dangerous-api/).

   Like the removed `timeout:` option, `Timeout.timeout(5)` inside the block is per-try — each retry gets a fresh 5-second budget. For an overall cap across all retries, use `max_elapsed_time:` instead.

Passing `timeout:` to `Retriable.retriable` or `Retriable.with_override` now raises `ArgumentError`. The `timeout` configuration attribute has also been removed, so `Retriable.configure { |c| c.timeout = 5 }` now raises `NoMethodError`.

## Installation

Via command line:

```ruby
gem install retriable
```

In your ruby script:

```ruby
require 'retriable'
```

In your Gemfile:

```ruby
gem 'retriable', '~> 4.0'
```

## Usage

Code in a `Retriable.retriable` block will be retried if an exception is raised.

```ruby
require 'retriable'

class Api
  # Use it in methods that interact with unreliable services
  def get
    Retriable.retriable do
      # code here...
    end
  end
end
```

### Defaults

By default, `Retriable` will:

- rescue any exception inherited from `StandardError`
- make 3 tries (including the initial attempt) before raising the last exception
- use randomized exponential backoff to calculate each succeeding try interval.

The default interval table with 10 tries looks like this (in seconds, rounded to the nearest millisecond):

| Retry # | Min      | Average  | Max      |
| ------- | -------- | -------- | -------- |
| 1       | `0.25`   | `0.5`    | `0.75`   |
| 2       | `0.375`  | `0.75`   | `1.125`  |
| 3       | `0.563`  | `1.125`  | `1.688`  |
| 4       | `0.844`  | `1.688`  | `2.531`  |
| 5       | `1.266`  | `2.531`  | `3.797`  |
| 6       | `1.898`  | `3.797`  | `5.695`  |
| 7       | `2.848`  | `5.695`  | `8.543`  |
| 8       | `4.271`  | `8.543`  | `12.814` |
| 9       | `6.407`  | `12.814` | `19.222` |
| 10      | **stop** | **stop** | **stop** |

### Options

Here are the available options, in some vague order of relevance to most common use patterns:

| Option                 | Default           | Definition                                                                                                                                                                                                                                                        |
| ---------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`tries`**            | `3`               | Number of attempts to make at running your code block (includes initial attempt). Pass `Float::INFINITY` to keep retrying until success or until `max_elapsed_time` is reached.                                                                                   |
| **`on`**               | `[StandardError]` | Type of exceptions to retry. [Read more](#configuring-which-options-to-retry-with-on).                                                                                                                                                                            |
| **`retry_if`**         | `nil`             | Callable (for example a `Proc` or lambda) that receives the rescued exception and returns true/false to decide whether to retry. [Read more](#advanced-retry-matching-with-retry_if).                                                                             |
| **`on_retry`**         | `nil`             | `Proc` to call after each try is rescued. Pass `false` to disable a callback set in `#configure` for a single call. [Read more](#callbacks).                                                                                                                      |
| **`on_give_up`**       | `nil`             | `Proc` to call when Retriable stops retrying after a rescued retriable exception. [Read more](#callbacks).                                                                                                                                                        |
| **`sleep_disabled`**   | `false`           | When true, disable exponential backoff and attempt retries immediately.                                                                                                                                                                                           |
| **`base_interval`**    | `0.5`             | The initial interval in seconds between tries.                                                                                                                                                                                                                    |
| **`max_elapsed_time`** | `900` (15 min)    | The maximum amount of total time in seconds that code is allowed to keep being retried. Set to `nil` to disable the time limit and retry based solely on `tries`.                                                                                                 |
| **`max_interval`**     | `60`              | The maximum interval in seconds that any individual retry can reach.                                                                                                                                                                                              |
| **`multiplier`**       | `1.5`             | Each successive interval grows by this factor. A multipler of 1.5 means the next interval will be 1.5x the current interval.                                                                                                                                      |
| **`rand_factor`**      | `0.5`             | The percentage to randomize the next retry interval time. The next interval calculation is `randomized_interval = retry_interval * (random value in range [1 - randomization_factor, 1 + randomization_factor])`                                                  |
| **`intervals`**        | `nil`             | Skip generated intervals and provide your own array of intervals in seconds. [Read more](#custom-interval-array).                                                                                                                                                 |

Timing options are validated before retrying. `tries` must be a positive integer when Retriable generates intervals, or `Float::INFINITY` for unbounded retries. `base_interval`, `max_interval`, `multiplier`, and `max_elapsed_time` must be non-negative numbers, with `max_elapsed_time` also accepting `nil`. `rand_factor` must be a number from `0` through `1`. If provided, `intervals` must be an array of non-negative numbers; because it replaces generated intervals, it also overrides `tries`, `base_interval`, `max_interval`, `rand_factor`, and `multiplier` validation. `intervals` cannot be combined with `tries: Float::INFINITY`.

#### Configuring Which Options to Retry With :on

**`:on`** Can take the form:

- An `Exception` class (retry every exception of this type, including subclasses)
- An `Array` or `Set` of `Exception` classes (retry any exception of one of these types, including subclasses)
- A `Hash` where the keys are `Exception` classes and the values are one of:
  - `nil` (retry every exception of the key's type, including subclasses)
  - A single `Regexp` pattern (retries exceptions ONLY if their `message` matches the pattern)
  - An array of patterns (retries exceptions ONLY if their `message` matches at least one of the patterns)

#### Advanced Retry Matching With :retry_if

Use **`:retry_if`** when retry logic depends on details that `:on` does not cover. The Proc receives the rescued exception and should return `true` to retry or `false` to re-raise immediately.

```ruby
def caused_by?(error, klass)
  current = error
  while current
    return true if current.is_a?(klass)

    current = current.cause
  end

  false
end

Retriable.retriable(
  on: [Faraday::ConnectionFailed],
  retry_if: ->(exception) { caused_by?(exception, Errno::ECONNRESET) }
) do
  # code here...
end
```

`:retry_if` runs after the exception type has matched `:on`.

### Configuration

You can change the global defaults with a `#configure` block:

```ruby
Retriable.configure do |c|
  c.tries = 5
  c.max_elapsed_time = 3600 # 1 hour
end
```

`#configure` sets defaults only. Per-call options passed to `Retriable.retriable` and
`Retriable.with_context` still take precedence.

When a higher-precedence layer sets `tries:` without `intervals:`, it clears any
`intervals:` inherited from a lower layer (so `retriable(tries: 1)` runs once even
if `intervals` was configured). Within a single call, passing `intervals:` still
overrides `tries:`.

### Override

`#with_override` is a block-scoped API for forcing retry options that should
take precedence over both `#configure` defaults and per-call options. It is
primarily intended for tests — it lets a test force values like `tries: 1` or
`base_interval: 0` so the suite runs quickly and predictably, regardless of
the application's `#configure` defaults. In application code, prefer
`#configure` for app-level defaults and per-call options for caller-specific
values.

```ruby
Retriable.with_override(tries: 1, base_interval: 0) do
  Retriable.retriable do
    # code here...
  end
end
```

Precedence inside the block:

```
with_override > local options > configure defaults
```

`#with_override` requires a block and raises `ArgumentError` if called without
one. The override is active only while the block is executing, and is
automatically restored to its previous value when the block returns or raises.
Nested `#with_override` calls work as expected: the inner block temporarily
replaces the active override and the outer override is restored when the
inner block exits.

`#with_override` is scoped to the **current thread**. The active override
does not affect any other thread, and child threads spawned inside the block
do not inherit it. This makes `#with_override` safe to use in parallel test
runners. Fibers running inside the same thread share the thread's active
override.

`#with_override` stores the provided options directly. Do not mutate the
options hash or nested values for the duration of the block.

For test-integration patterns (RSpec `around`, helper methods, Minitest, etc.),
see [docs/testing.md](docs/testing.md).

### Example Usage

This example will only retry on a `Timeout::Error`, retry 3 times and sleep for a full second before each try.

```ruby
require "timeout"

Retriable.retriable(on: Timeout::Error, tries: 3, base_interval: 1) do
  # code here...
end
```

You can also specify multiple errors to retry on by passing an array of exceptions.

```ruby
require "timeout"

Retriable.retriable(on: [Timeout::Error, Errno::ECONNRESET]) do
  # code here...
end
```

You can also use a hash to specify that you only want to retry exceptions with certain messages (see [the documentation above](#configuring-which-options-to-retry-with-on)). This example will retry all `ActiveRecord::RecordNotUnique` exceptions, `ActiveRecord::RecordInvalid` exceptions where the message matches either `/Parent must exist/` or `/Username has already been taken/`, or `Mysql2::Error` exceptions where the message matches `/Duplicate entry/`.

```ruby
Retriable.retriable(on: {
  ActiveRecord::RecordNotUnique => nil,
  ActiveRecord::RecordInvalid => [/Parent must exist/, /Username has already been taken/],
  Mysql2::Error => /Duplicate entry/
}) do
  # code here...
end
```

If you need millisecond units of time for the sleep interval:

```ruby
Retriable.retriable(base_interval: (200 / 1000.0)) do
  # code here...
end
```

### Custom Interval Array

You can also bypass the built-in interval generation and provide your own array of intervals. Supplying your own intervals overrides the `tries`, `base_interval`, `max_interval`, `rand_factor`, and `multiplier` parameters.

```ruby
Retriable.retriable(intervals: [0.5, 1.0, 2.0, 2.5]) do
  # code here...
end
```

This example makes 5 total attempts. If the first attempt fails, the 2nd attempt occurs 0.5 seconds later.

### Unbounded Retries (Opt-in)

You can opt in to unbounded retries with `tries: Float::INFINITY`. This is useful for long-running worker processes where retrying should continue indefinitely, but it must be used with care.

```ruby
Retriable.retriable(tries: Float::INFINITY, max_elapsed_time: 300) do
  # code here...
end
```

When `tries: Float::INFINITY` is set:

- `max_elapsed_time` must be a finite number. Retriable raises `ArgumentError` if it is `nil` or `Float::INFINITY`. This is a safety bound that prevents accidentally unbounded loops.
- Custom `intervals:` cannot be combined with `Float::INFINITY` and raises `ArgumentError`. Use the exponential backoff settings (`base_interval`, `multiplier`, `max_interval`, `rand_factor`) instead.

### Turn off Exponential Backoff

Exponential backoff is enabled by default. If you want to simply retry code every second, 5 times maximum, you can do this:

```ruby
Retriable.retriable(tries: 5, base_interval: 1.0, multiplier: 1.0, rand_factor: 0.0) do
  # code here...
end
```

This works by starting at a 1 second `base_interval`. Setting the `multipler` to 1.0 means each subsequent try will increase 1x, which is still `1.0` seconds, and then a `rand_factor` of 0.0 means that there's no randomization of that interval. (By default, it would randomize 0.5 seconds, which would mean normally the intervals would randomize between 0.5 and 1.5 seconds, but in this case `rand_factor` is basically being disabled.)

Another way to accomplish this would be to create an array with a fixed interval. In this example, `Array.new(5, 1)` creates an array with 5 elements, all with the value 1. The code block will retry up to 5 times, and wait 1 second between each attempt.

```ruby
# Array.new(5, 1) # => [1, 1, 1, 1, 1]

Retriable.retriable(intervals: Array.new(5, 1)) do
  # code here...
end
```

If you don't want exponential backoff but you still want some randomization between intervals, this code will run every 1 seconds with a randomization factor of 0.2, which means each interval will be a random value between 0.8 and 1.2 (1 second +/- 0.2):

```ruby
Retriable.retriable(base_interval: 1.0, multiplier: 1.0, rand_factor: 0.2) do
  # code here...
end
```

### Callbacks

`#retriable` also provides a callback called `:on_retry` that will run after an exception is rescued. This callback provides the `exception` that was raised in the current try, the `try_number`, the `elapsed_time` for all tries so far, and the time in seconds of the `next_interval`. As these are specified in a `Proc`, unnecessary variables can be left out of the parameter list.

```ruby
do_this_on_each_retry = Proc.new do |exception, try, elapsed_time, next_interval|
  log "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
end

Retriable.retriable(on_retry: do_this_on_each_retry) do
  # code here...
end
```

#### Disabling a Configured Callback Per Call

If `on_retry` is set in `Retriable.configure`, every call uses it by default. To opt a specific call out — for example, a critical call site that should not log on retry — pass `on_retry: false` or `on_retry: nil`.

```ruby
Retriable.configure do |c|
  c.on_retry = ->(exception, try, elapsed_time, next_interval) { log(...) }
end

# Most calls use the configured callback.
Retriable.retriable do
  # ...
end

# This specific call opts out of the configured callback.
Retriable.retriable(on_retry: false) do
  # ...
end
```

You can also use `:on_give_up` to run a callback when Retriable stops retrying after a rescued retriable exception. This callback receives the `exception`, the `try_number`, the `elapsed_time` for all tries so far, the `next_interval`, and the `reason` Retriable is giving up. The `reason` is either `:tries_exhausted` or `:max_elapsed_time`.

```ruby
do_this_when_retries_stop = Proc.new do |exception, try, elapsed_time, next_interval, reason|
  log "#{exception.class}: '#{exception.message}' - gave up after #{try} tries because #{reason}."
end

Retriable.retriable(on_give_up: do_this_when_retries_stop) do
  # code here...
end
```

When the reason is `:tries_exhausted`, `next_interval` is `nil` because there is no next retry. When the reason is `:max_elapsed_time`, `next_interval` is the interval that would have been slept before the next try. This reason means the next retry would exceed `max_elapsed_time`, not necessarily that the elapsed time has already exceeded it.

If both `:on_retry` and `:on_give_up` are configured, `:on_retry` still runs first for the final rescued retriable exception. This preserves the existing behavior that `:on_retry` runs whenever Retriable rescues an exception that matches its retry rules.

If you configure a default `:on_give_up` callback but want to suppress it for a specific call, pass `on_give_up: false` (or `nil`). Both are treated as "no callback".

`:on_give_up` is invoked only when Retriable rescued an exception that matched the retry rules and then decided to stop. It does **not** fire when the block raises an exception that is not in `:on`, nor when `:retry_if` returns false. Both of those cases are immediate re-raises, not retry exhaustion, and should be handled with normal Ruby `rescue` blocks around the `Retriable.retriable` call.

If `:on_give_up` itself raises, that exception propagates to the caller and replaces the original retried exception. Keep the handler defensive (rescue inside it) if you need the original exception to surface.

### Ensure/Else

What if I want to execute a code block at the end, whether or not an exception was rescued ([ensure](http://ruby-doc.org/docs/keywords/1.9/Object.html#method-i-ensure))? Or what if I want to execute a code block if no exception is raised ([else](http://ruby-doc.org/docs/keywords/1.9/Object.html#method-i-else))? Instead of providing more callbacks, I recommend you just wrap retriable in a begin/retry/else/ensure block:

```ruby
begin
  Retriable.retriable do
    # some code
  end
rescue => e
  # run this if retriable ends up re-raising the exception
else
  # run this if retriable doesn't raise any exceptions
ensure
  # run this no matter what, exception or no exception
end
```

## Contexts

Contexts allow you to coordinate sets of Retriable options across an application. Each context is basically an argument hash for `Retriable.retriable` that is stored in the `Retriable.config` as a simple `Hash` and is accessible by name. For example:

```ruby
Retriable.configure do |c|
  c.contexts[:aws] = {
    tries: 3,
    base_interval: 5,
    on_retry: Proc.new { puts 'Curse you, AWS!' },
    on_give_up: Proc.new { |_e, _try, _elapsed, _interval, reason| puts "Gave up on AWS: #{reason}" }
  }
  c.contexts[:mysql] = {
    tries: 10,
    multiplier: 2.5,
    on: Mysql::DeadlockException
  }
end
```

This will create two contexts, `aws` and `mysql`, which allow you to reuse different backoff strategies across your application without continually passing those strategy options to the `retriable` method.

These are used simply by calling `Retriable.with_context`:

```ruby
# Will retry all exceptions
Retriable.with_context(:aws) do
  # aws_call
end

# Will retry Mysql::DeadlockException
Retriable.with_context(:mysql) do
  # write_to_table
end
```

You can even temporarily override individual options for a configured context:

```ruby
Retriable.with_context(:mysql, tries: 30) do
  # write_to_table with :mysql context, except with 30 tries instead of 10
end
```

## Kernel Extension

If you want to call `Retriable.retriable` without the `Retriable` module prefix and you don't mind extending `Kernel`,
there is a kernel extension available for this.

In your ruby script:

```ruby
require 'retriable/core_ext/kernel'
```

or in your Gemfile:

```ruby
gem 'retriable', require: 'retriable/core_ext/kernel'
```

and then you can call `#retriable` in any context like this:

```ruby
retriable do
  # code here...
end

retriable_with_context(:api) do
  # code here...
end
```

## Testing

`Retriable.with_override` is designed to short-circuit retries in your test
suite so failing blocks do not slow tests down. The simplest pattern is an
RSpec `around(:each)` hook (or your test framework's equivalent) that wraps
every example in `with_override(tries: 1, base_interval: 0)`.

For Rails integration, opting out of the override for specific tests, and
overriding configured contexts in tests, see
[docs/testing.md](docs/testing.md).

## Credits

The randomized exponential backoff implementation was inspired by the one used in Google's [google-http-java-client](https://code.google.com/p/google-http-java-client/wiki/ExponentialBackoff) project.

## Development

### Running Specs

```bash
bundle exec rspec
```
