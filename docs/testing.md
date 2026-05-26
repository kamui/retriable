# Testing with Retriable

`Retriable.with_override` exists primarily for tests. It lets a test force
retry options like `tries: 1` or `base_interval: 0` so the suite runs quickly
and predictably, regardless of what the application's `Retriable.configure`
defaults are.

`with_override` is block-scoped: the override is active inside the block and
restored to its previous value (which is usually "no override") when the block
exits, even if the block raises. It is also thread-local — overrides set in
one thread do not affect other threads — so it is safe for parallel test
runners. See the README for the full API contract.

## RSpec

### Apply an override to every test

Use `around(:each)` in `RSpec.configure` so every test in the suite runs inside
the override. This is the most common pattern:

```ruby
RSpec.configure do |config|
  config.around(:each) do |example|
    Retriable.with_override(tries: 1, base_interval: 0) do
      example.run
    end
  end
end
```

### Apply an override to a specific context

```ruby
describe MyClient do
  context "when external calls should not retry" do
    around(:each) do |example|
      Retriable.with_override(tries: 1) { example.run }
    end

    it "fails fast" do
      # `with_override(tries: 1)` is active here
    end
  end
end
```

### Apply an override to a single test

Wrap the test body directly:

```ruby
it "does the thing without waiting" do
  Retriable.with_override(tries: 1, base_interval: 0) do
    # test body
  end
end
```

### Reusable helper

Wrap a common configuration in a helper to keep tests readable:

```ruby
module RetriableHelpers
  def with_fast_retries(&block)
    Retriable.with_override(tries: 1, base_interval: 0, &block)
  end
end

RSpec.configure do |config|
  config.include RetriableHelpers
end

# In a spec:
it "does the thing" do
  with_fast_retries do
    # test body
  end
end
```

## Minitest

```ruby
class MyClientTest < Minitest::Test
  def around
    Retriable.with_override(tries: 1, base_interval: 0) { yield }
  end

  def test_fails_fast
    # `with_override(tries: 1)` is active here
  end
end
```

Older Minitest versions without `around` can wrap the test body directly:

```ruby
def test_fails_fast
  Retriable.with_override(tries: 1) do
    # test body
  end
end
```

## Short-Circuiting Retriable in Your Test Suite

When you are running tests for your app, the default retry behavior (3 tries
with exponential backoff) makes failing blocks take a long time. To short-circuit
retries — including calls that pass local options — set `tries: 1` and disable
backoff using `with_override`.

### Under Rails

Keep shared defaults in `Retriable.configure` and apply test-only overrides via
RSpec's `around` hook (or your test framework's equivalent):

```ruby
# config/initializers/retriable.rb
Retriable.configure do |c|
  c.tries = 3
  c.base_interval = 0.5
  c.rand_factor = 0.5
end

# spec/spec_helper.rb (or equivalent)
RSpec.configure do |config|
  config.around(:each) do |example|
    Retriable.with_override(tries: 1, base_interval: 0, rand_factor: 0) do
      example.run
    end
  end
end
```

If a specific test needs normal retry behavior, opt out by running outside the
`around` hook. The cleanest way is to tag the example and skip the hook for
tagged examples:

```ruby
config.around(:each, retriable: :real) { |example| example.run }
config.around(:each) do |example|
  next example.run if example.metadata[:retriable] == :real

  Retriable.with_override(tries: 1, base_interval: 0, rand_factor: 0) do
    example.run
  end
end

it "exercises the real retry behavior", retriable: :real do
  # `with_override` is not applied here
end
```

### Overriding Configured Contexts in Tests

If you have configured contexts, top-level override values (such as `tries: 1`)
already take precedence over context-specific values. To override
context-specific options as well (for example, clearing a context's
`:intervals` array or shrinking its `:on` exception list), pass `:contexts` to
`with_override`.

Given a configured `google_api` context:

```ruby
# config/initializers/retriable.rb
Retriable.configure do |c|
  c.contexts[:google_api] = {
    tries:         5,
    base_interval: 3,
    on: [
      Net::ReadTimeout,
      Signet::AuthorizationError,
      Errno::ECONNRESET,
      OpenSSL::SSL::SSLError,
    ],
  }
end
```

You can override both top-level defaults and per-context options in your
test setup:

```ruby
RSpec.configure do |config|
  config.around(:each) do |example|
    context_overrides = Retriable.config.contexts.each_key.with_object({}) do |key, h|
      h[key] = { tries: 1, base_interval: 0 }
    end

    Retriable.with_override(
      multiplier: 1.0,
      rand_factor: 0.0,
      base_interval: 0,
      contexts: context_overrides,
    ) do
      example.run
    end
  end
end
```

## Notes

- The override is automatically cleared when the block exits, including when
  the block raises. You do not need to clean up after the block.
- `with_override` calls nest: an inner block temporarily replaces the active
  override, and the outer override is restored when the inner block exits.
- Overrides are thread-local. Child threads spawned inside the block do not
  inherit it. If a test spawns background threads that themselves call
  `Retriable.retriable`, wrap each background thread's body in its own
  `with_override` call.
