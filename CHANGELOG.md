## 1.4.1
* Fixes non kernel mode bug. Remove DSL class, move `#retriable` into Retriable module. Thanks @mkrogemann.

## 1.4.0
* By default, retriable doesn't monkey patch `Kernel`. If you want this functionality,
you can `require 'retriable/core_ext/kernel'.
* Upgrade minitest to 5.x.
* Refactor the DSL into it's own class.

## 1.3.3.1
* Allow sleep parameter to be a proc/lambda to allow for exponential backoff.

## 1.3.3
* sleep after executing the retry block, so there's no wait on the first call (molfar)

## 1.3.2
* Clean up option defaults.
* By default, rescue StandardError and Timeout::Error instead of [Exception](http://www.mikeperham.com/2012/03/03/the-perils-of-rescue-exception).

## 1.3.1
* Add `rake` dependency for travis-ci.
* Update gemspec summary and description.

## 1.3.0

* Rewrote a lot of the code with inspiration from [attempt](https://rubygems.org/gems/attempt).
* Add timeout option to the code block.
* Include in Kernel by default, but allow require 'retriable/no_kernel' to load a non kernel version.
* Renamed `:times` option to `:tries`.
* Renamed `:sleep` option to `:interval`.
* Renamed `:then` option to `:on_retry`.
* Removed other callbacks, you can wrap retriable in a begin/rescue/else/ensure block if you need that functionality. It avoids the need to define multiple Procs and makes the code more readable.
* Rewrote most of the README

## 1.2.0

* Forked the retryable-rb repo.
* Extend the Kernel module with the retriable method so you can use it anywhere without having to include it in every class.
* Update gemspec, Gemfile, and Raketask.
* Remove echoe dependency.
