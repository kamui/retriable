Introduction
============

Retriable is an easy to use DSL to retry code if an exception is raised.  This is especially useful when interacting with unreliable services that fail randomly.

Installation
------------

    gem install retriable

    # In your ruby application
    require 'retriable'

    # In your Gemfile
    gem 'retriable'

Using Retriable
---------------

Code wrapped in a retriable block will be retried if a failure occurs.  As such, code attempted once, will be retried again for another attempt if it fails to run.

    require 'retriable'

    class Api
      # Use it in methods that interact with unreliable services
      def get
        retriable do
          # code here...
        end
      end
    end

By default, Retriable will rescue any exception inherited from `Exception`, retry once (for a total of two attempts) and sleep for a random amount time (between 0 to 100 milliseconds, in 10 millisecond increments).  You can choose additional options by passing them via an options `Hash`.

    retriable :on => Timeout::Error, :times => 3, :sleep => 1 do
      # code here...
    end

This example will only retry on a `Timeout::Error`, retry 3 times (for a total of 4 attempts) and sleep for a full second before each retry.  You can also specify multiple errors to retry on by passing an array.

    retriable :on => [Timeout::Error, Errno::ECONNRESET] do
      # code here...
    end

You can also have Ruby retry immediately after a failure by passing `false` as the sleep option.

    retriable :sleep => false do
      # code here...
    end

Retriable also allows for callbacks to be defined, which is useful to log failures for analytics purposes or cleanup after repeated failures.  Retriable has three types of callbacks: `then`, `finally`, and `always`.

`then`: Run every time a failure occurs.

`finally`: Run when the number of retries runs out.

`always`: Run when the code wrapped in a retriable block passes or when the number of retries runs out.

The `then` and `finally` callbacks pass the exception raised, which can be used for logging or error control.  All three callbacks also have a `handler`, which provides an interface to pass data between the code wrapped in the retriable block and the callbacks defined.

Furthermore, each callback provides the number of `attempts`, `retries` and `times` that the wrapped code should be retried.  As these are specified in a `Proc`, unnecessary variables can be left out of the parameter list.

    then_cb = Proc.new do |exception, handler, attempts, retries, times|
      log "#{exception.class}: '#{exception.message}' - #{attempts} attempts, #{retries} out of #{times} retries left."}
    end

    finally_cb = Proc.new do |exception, handler|
      log "#{exception.class} raised too many times. First attempt at #{handler[:start]} and final attempt at #{Time.now}"
    end

    always_cb = Proc.new do |handler, attempts|
      log "total time for #{attempts} attempts: #{Time.now - handler[:start]}"
    end

    retriable :then => then_cb do, :finally => finally_cb, :always => always_cb |handler|
      handler[:start] ||= Time.now

      # code here...
    end

Credits
-------

Retriable was originally forked from the retryable-rb gem by [Robert Sosinski](https://github.com/robertsosinski), which in turn originally inspired by code written by [Michael Celona](http://github.com/mcelona) and later assisted by [David Malin](http://github.com/dmalin).