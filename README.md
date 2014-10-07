#Retriable

[![Build Status](https://secure.travis-ci.org/kamui/retriable.png)](http://travis-ci.org/kamui/retriable)

Retriable is an simple DSL to retry failed code blocks with randomized [exponential backoff](http://en.wikipedia.org/wiki/Exponential_backoff). This is especially useful when interacting external api/services or file system calls.

## Requirements

Ruby 2.0+

If you need 1.9.x support, use the [1.x branch](https://github.com/kamui/retriable/tree/1.x).

WARNING: 2.x isn't API compatible with 1.x.

## Installation

via command line:

```ruby
gem install retriable
```

In your ruby script:

```ruby
require 'retriable'
```

In your Gemfile:

```ruby
gem 'retriable'
```

## Usage

Code in a `Retriable.retry` block will be retried if an exception is raised. By default, Retriable will rescue any exception inherited from `StandardError`, make 3 retry attempts before raising the last exception, and also use randomized exponential backoff to calculate each succeeding attempt interval. The default interval table with 10 attempts looks like this (in seconds):

| request# | retry interval | randomized interval |
| -------- | -------------- | ------------------- |
| 1        |    0.5         |   [0.25,   0.75]    |
| 2        |    0.75        |   [0.375,  1.125]   |
| 3        |    1.125       |   [0.562,  1.687]   |
| 4        |    1.687       |   [0.8435, 2.53]    |
| 5        |    2.53        |   [1.265,  3.795]   |
| 6        |    3.795       |   [1.897,  5.692]   |
| 7        |    5.692       |   [2.846,  8.538]   |
| 8        |    8.538       |   [4.269, 12.807]   |
| 9        |   12.807       |   [6.403, 19.210]   |
| 10       |   19.210       |   stop              |

```ruby
require 'retriable'

class Api
  # Use it in methods that interact with unreliable services
  def get
    Retriable.retry do
      # code here...
    end
  end
end
```

### Options

Here are the available options:

`max_tries` (default: 3) - Number of attempts to make at running your code block.

`base_interval` (default: 0.5) - The initial interval in seconds between attempts.

`max_interval` (default: 60) - The maximum interval in seconds that any attempt can climb to.

`rand_factor` (default: 0.25) - The percent range above and below the next interval is randomized between. The calculation is calculated like this:

```
randomized_interval = retry_interval * (random value in range [1 - randomization_factor, 1 + randomization_factor])
```

`multiplier` (default: 1.5) - Each successive interval grows by this factor. A multipler of 1.5 means the next interval will be 1.5x the current interval.

`max_elapsed_time`  (default: 900 (15 min)) - The maximum amount of total time that code is allowed to keep being retried.

`intervals`  (default: nil) - Skip generated intervals and provide your own array of intervals in seconds. Setting this option will ignore `max_tries`, `base_interval`, `max_interval`, `rand_factor`, and `multiplier` values.

`timeout` (default: 0) - Number of seconds to allow the code block to run before raising a Timeout::Error

`on` (default: [StandardError]) - An `Array` of exceptions to rescue for each attempt, a `Hash` where the keys are `Exception` classes and the values can be a single `Regexp` pattern or a list of patterns, or a single `Exception` type.

`on_retry` - (default: nil) - Proc to call after each attempt is rescued.

### Config

You can change the global defaults with a `#configure` block:

```ruby
Retriable.configure do |c|
  c.max_tries = 5
  c.max_elapsed_time = 3600 # 1 hour
end
```

### Examples

`Retriable.retry` accepts custom arguments. This example will only retry on a `Timeout::Error`, retry 3 times and sleep for a full second before each attempt.

```ruby
Retriable.retry on: Timeout::Error, max_tries: 3, base_interval: 1 do
  # code here...
end
```

You can also specify multiple errors to retry on by passing an array of exceptions.

```ruby
Retriable.retry on: [Timeout::Error, Errno::ECONNRESET] do
  # code here...
end
```

You can also specify a Hash of exceptions where the values are a list or single Regexp pattern.

```ruby
Retriable.retry on: {
  ActiveRecord::RecordNotUnique => nil,
  ActiveRecord::RecordInvalid => [/Email has already been taken/, /Username has already been taken/],
  Mysql2::Error => /Duplicate entry/
} do
  # code here...
end
```

You can also specify a timeout if you want the code block to only make an attempt for X amount of seconds. This timeout is per attempt.

```ruby
Retriable.retry timeout: 60 do
  # code here...
end
```

If you need millisecond units of time for the sleep or the timeout:

```ruby
Retriable.retry base_interval: (200/1000.0), timeout: (500/1000.0) do
  # code here...
end
```

### Custom Interval Array

You can also bypass the built-in interval generation and provide your own array of intervals. Supplying your own intervals overrides the `max_tries`, `base_interval`, `max_interval`, `rand_factor`, and `multiplier` parameters.

```ruby
Retriable.retry intervals: [0.5, 1.0, 2.0, 2.5] do
  # code here...
end
```

### Turn off Exponential Backoff

Exponential backoff is enabled by default, if you want to simply execute code every second, you can do this:

```ruby
Retriable.retry base_interval: 1.0, multiplier: 1.0, rand_factor: 0.0 do
  # code here...
end
```

If you don't want exponential backoff, but you still want some randomization between intervals, this code will run every 1 seconds with a randomization factor of 0.2, which means each interval will be a random value between 0.8 and 1.2 (1 second +/- 0.2):

```ruby
Retriable.retry base_interval: 1.0, multiplier: 1.0, rand_factor: 0.2 do
  # code here...
end
```

### Callbacks

Retriable.retry also provides a callback called `:on_retry` that will run after an exception is rescued. This callback provides the `exception` that was raised in the current attempt, the `try_number`, the `elapsed_time` for all attempts so far, and the time in seconds of the `next_interval`. As these are specified in a `Proc`, unnecessary variables can be left out of the parameter list.

```ruby
do_this_on_each_retry = Proc.new do |exception, try_number, elapsed_time, next_interval|
  log "#{exception.class}: '#{exception.message}' - #{try_number} attempts in #{elapsed_time} seconds and #{next_interval} seconds until the next attempt."}
end

Retriable.retry on_retry: do_this_on_each_retry do
  # code here...
end
```

### Ensure/Else

What if I want to execute a code block at the end, whether or not an exception was rescued ([ensure](http://ruby-doc.org/docs/keywords/1.9/Object.html#method-i-ensure))? Or, what if I want to execute a code block if no exception is raised ([else](http://ruby-doc.org/docs/keywords/1.9/Object.html#method-i-else))? Instead of providing more callbacks, I recommend you just wrap retriable in a begin/retry/else/ensure block:

```ruby
begin
  Retriable.retry do
    # some code
  end
rescue => e
  # run this if retriable ends up re-rasing the exception
else
  # run this if retriable doesn't raise any exceptions
ensure
  # run this no matter what, exception or no exception
end
```

## Kernel Extension

If you want to call `Retriable.retry` without the `Retriable` module prefix and you don't mind extending `Kernel`,
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
```

## Credits

Retriable was originally forked from the retryable-rb gem by [Robert Sosinski](https://github.com/robertsosinski), which in turn originally inspired by code written by [Michael Celona](http://github.com/mcelona) and later assisted by [David Malin](http://github.com/dmalin). The [attempt](https://rubygems.org/gems/attempt) gem by Daniel J. Berger was also an inspiration.
