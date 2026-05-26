# Design: `on_give_up` callback follow-ups (issue #72, PR #127)

## Context

- Issue [#72](https://github.com/kamui/retriable/issues/72) requests a callback that fires only after all retries are exhausted.
- Draft PR [#127](https://github.com/kamui/retriable/pull/127) (branch `feat/on-give-up-callback`, authored by maintainer @kamui) implements this as `on_give_up`. It is largely production-ready.

This spec defines a small set of follow-up additions on top of `feat/on-give-up-callback`. It does **not** revisit the design decisions already settled in #127 (naming, signature, reason symbols, opt-out behavior).

## Settled decisions inherited from #127

| Decision | Resolution |
| --- | --- |
| Callback name | `on_give_up` |
| Signature | `(exception, try, elapsed_time, next_interval, reason)` |
| Reason values | `:tries_exhausted`, `:max_elapsed_time` |
| `next_interval` when `:tries_exhausted` | `nil` |
| `next_interval` when `:max_elapsed_time` | The interval that would have been slept before the next try |
| Opt-out | `on_give_up: false` (or `nil`) disables a configured handler |
| Order vs `on_retry` | `on_retry` runs first; `on_give_up` runs just before re-raise |
| Non-retriable exception types | `on_give_up` does **not** fire |
| `retry_if` rejection | `on_give_up` does **not** fire |
| `elapsed_time` for the give-up decision | Re-read after `on_retry` returns so handler time counts toward `max_elapsed_time` |
| Threading through `Config::ATTRIBUTES` | Already enables `with_context`, `override`, and `configure` automatically |

## Gaps to fill

PR #127 has the mechanics right. The follow-up work below closes documentation and test-coverage gaps and locks in undocumented-but-implied semantics.

### 1. Document non-firing cases in README

PR #127 covers the firing cases. The README should explicitly state when the callback does **not** fire, because users wiring up paging/metrics need to know.

Add one paragraph at the end of the new `on_give_up` subsection in `README.md`:

> `on_give_up` is invoked only when Retriable rescued an exception that matched the retry rules and then decided to stop. It does **not** fire when the block raises an exception that is not in `on`, nor when `retry_if` returns false. Both of those cases are immediate re-raises, not retry exhaustion, and should be handled with normal Ruby `rescue` blocks around the `Retriable.retriable` call.

### 2. Document handler-raised-error policy in README

Current `on_retry` documentation does not state what happens if the handler itself raises. PR #127 silently inherits the same behavior: an exception inside `on_give_up` propagates, replacing the original. Make this explicit.

Add one sentence to the same subsection:

> If `on_give_up` itself raises, that exception propagates to the caller and replaces the original retried exception. Keep the handler defensive (rescue inside it) if you need the original exception to surface.

### 3. Mention `on_give_up` in the Contexts example

`README.md` already has a Contexts example at `README.md:306`. Extend the `:aws` context to demonstrate `on_give_up`:

```ruby
Retriable.configure do |c|
  c.contexts[:aws] = {
    tries: 3,
    base_interval: 5,
    on_retry: Proc.new { puts 'Curse you, AWS!' },
    on_give_up: Proc.new { |_e, _try, _elapsed, _interval, reason|
      puts "Gave up on AWS: #{reason}"
    },
  }
end
```

### 4. Test: per-context `override` accepts and dispatches `on_give_up`

PR #127 adds a positive `with_context` spec and an `override` spec for top-level overrides, but no spec for the call shape `Retriable.override(contexts: { key: { on_give_up: ... } })`, which is validated by `validate_context_override_options` and applied by `context_options_for`. Add one spec under the existing `#override` context that:

1. Calls `Retriable.override(contexts: { api: { on_give_up: handler, tries: 1 } })`.
2. Invokes `Retriable.with_context(:api) { raise StandardError }`.
3. Asserts the handler was invoked exactly once with `reason == :tries_exhausted`.

### 5. Test: kernel extension passes `on_give_up` through

PR #127 does not exercise the kernel extension (`Kernel#retriable` and `Kernel#retriable_with_context`). The delegation is trivial, but a regression guard is cheap. Add one spec inside the existing `context "global scope extension"` block that requires `retriable/core_ext/kernel`, invokes `retriable(tries: 1, on_give_up: handler) { raise }`, and asserts the handler ran with `reason == :tries_exhausted`. A second `retriable_with_context` spec is not needed because item 4 already covers the context-dispatch path.

### 6. Test: handler that raises propagates and replaces the original

Lock in the policy from item 2 with a spec: handler raises `RuntimeError`, caller observes `RuntimeError`, not the original `StandardError`.

### 7. CHANGELOG entry: include signature and reasons

PR #127's CHANGELOG line is:

> - Add `on_give_up` callback to observe when retries stop because tries are exhausted or the next retry would exceed `max_elapsed_time`.

Rewrite to:

> - Add `on_give_up` callback that runs when Retriable stops retrying after a rescued retriable exception. Receives `(exception, try, elapsed_time, next_interval, reason)`, where `reason` is `:tries_exhausted` or `:max_elapsed_time`. Does not fire for non-retriable exceptions or `retry_if` rejections. Pass `on_give_up: false` to suppress a configured handler for a single call.

## Out of scope

- Renaming `on_give_up`. The maintainer authored the draft with this name.
- Changing the callback signature (e.g., removing `next_interval`).
- Firing for `retry_if` rejection. That decision was made deliberately in #127.
- Version bump. Deferred to the maintainer's release commit.
- Touching the pre-existing rubocop offenses noted in PR #127's description (`retriable.gemspec`, `spec/exponential_backoff_spec.rb`).

## Files touched

- `README.md` — items 1, 2, 3.
- `spec/retriable_spec.rb` — items 4, 5, 6.
- `CHANGELOG.md` — item 7.

No changes to `lib/retriable.rb` or `lib/retriable/config.rb`; PR #127's implementation already satisfies the behavior.

## Verification

```sh
bundle exec rspec
bundle exec rubocop lib spec
```

Both must pass. Pre-existing rubocop offenses in `retriable.gemspec` and `spec/exponential_backoff_spec.rb` are intentionally left untouched (see Out of scope).

## Delivery

Push as additional commits on the existing `feat/on-give-up-callback` branch (PR #127). If we lack push access to the maintainer's branch, open a PR targeting `feat/on-give-up-callback` with these follow-ups, or post the diff as a review comment on #127.
