# 1. Copy-on-write config publication

## Status

Accepted.

## Context

`Retriable.config` is a single mutable object read on every `Retriable.retriable`
call and written rarely, usually once at boot. That shape had three races:

- `@config ||= Config.new` was check-then-act, so two threads booting at once
  could build two different `Config` objects.
- `retriable` read attributes off the live shared config one at a time, so a
  concurrent `configure` could hand a single call an inconsistent mix of old and
  new values.
- `with_context` read the config more than once. The existence check and the
  option resolution could straddle a `configure`. The check could pass against
  the old snapshot before resolution silently dropped the context's retry
  options from the new one.

Reads vastly outnumber writes, so a scheme that keeps readers cheap and pays the
cost on the writer is the right trade.

## Decision

Configuration is copy-on-write.

`configure` takes `CONFIG_MUTEX`, duplicates the published config, yields the
duplicate, and publishes it only if the block returns without raising. Writers
serialize against each other; a raising block leaves the previous config in
place. Publication does not change the method's return contract: `configure`
returns the block's result, not the candidate or published snapshot.

**One publication seam, one engine path.** `CONFIG_PUBLICATION_MUTEX` guards the
`@config` reference and is held only for a reference read or the publishing
write, never across the user's block, so a writer blocks a reader for no longer
than a pointer swap. We do not special-case MRI. An unsynchronized read would be
safe there thanks to the GVL, but it would leave a second memory model to
maintain for JRuby and TruffleRuby.

The mutex is part of the hot path. A `retriable` call with no local options or
override uses the published `Config` directly, so it does not otherwise pay for
`Config.new`, `to_h`, or a merge. `benchmark/config_publication.rb` measures both
raw config reads and successful retry calls with one or more reader threads. We
accept the mutex cost for a portable memory-visibility guarantee, but we do not
assume that cost is free. If the benchmark shows material contention on a
supported engine, `Concurrent::AtomicReference` is the preferred alternative.
An engine-conditional unsynchronized read is not.

**The published snapshot is deeply frozen.** Atomic publication alone does not
deliver a consistent read: if the published object stays mutable, any caller can
still do `Retriable.config.contexts[:api][:tries] = 1` and corrupt what every
other thread is reading. `Config#freeze` therefore freezes `on`, `intervals` and
`contexts` recursively before freezing the config itself. `configure` publishes a
*copy* of the candidate so freezing never reaches a container the caller still
owns (`c.on = my_array` must not leave `my_array` frozen).

**`dup` copies containers, not leaves, and never preserves frozen state.**
`Config#initialize_copy` deep-copies `on`, `intervals` and `contexts`; scalars,
procs, exception classes and regexps are shared by reference. A Hash's mutable
default *value* is part of the copied graph, because a shared one would let
`config.contexts[:absent] << x` reach the caller's object; a `default_proc`
remains a shared callable leaf. Copies start from `#dup` rather than a fresh
literal so a container's class and a Hash's default behavior survive. Rebuilding
into a bare `{}` would silently downgrade an indifferent-access `contexts` hash
and break string-key lookups. Frozen state is deliberately dropped, because a dup
is the mutable working copy a `configure` block mutates; publication re-freezes
it.

Hash *keys* are left as-is. Ruby already dups and freezes an unfrozen String key
on assignment. The supported key types, Symbols for `contexts` and exception
classes for `on`, are immutable. Copying keys would buy immutability only for
container keys, still miss arbitrary mutable objects, and break `compare_by_identity`
lookups, so the boundary stays where Ruby puts it.

Deep immutability covers the containers owned by `Config`. Callable leaves can
hold their own mutable state, and a shared `default_proc` can mutate state outside
the config. Callers remain responsible for synchronizing that state when the
callable runs from multiple threads.

**Two mechanisms, two questions.** A thread-local (`CONFIGURING_THREAD_KEY`)
answers "is this thread mid-`configure`?", which is what lets the configuring
thread and its fibers see their own candidate. Which snapshot a *single*
`retriable`/`with_context` call resolves against is a different question,
answered by passing that snapshot as an argument to `retriable_with_config`. A
thread-local would leak the resolved snapshot across the caller's block and
change what `Retriable.config` returns inside it, so the two are kept apart. The
snapshot travels one hop; `with_context` resolves its contexts hash once and
passes that.

**Nested calls join the outer transaction.** A nested `configure` sees the
candidate stored in `CONFIGURING_THREAD_KEY` and yields that same object without
taking `CONFIG_MUTEX` again. This preserves the behavior supported before
copy-on-write and avoids recursive locking. The outermost block alone publishes.
If it raises, Retriable discards every change made by nested blocks. A nested call
does not create an independent commit or savepoint. Fibers on the configuring
thread share the transaction because `CONFIGURING_THREAD_KEY` is a true thread
local.

## Consequences

- Direct mutation of `Retriable.config` now raises `FrozenError`. This is a
  breaking change for code that reached around `configure`; the migration is to
  use `configure`. Reading `Retriable.config` is unaffected. This must ship in a
  major release or follow a deprecation cycle.
- Nested `configure` remains supported. Nested blocks mutate the outer working
  copy and do not publish separately.
- `configure` pays two deep copies per call (one to build the candidate, one to
  take ownership before freezing). `configure` is a rare, usually boot-time
  operation, so this is not on any hot path.
- Every `retriable` call takes one uncontended mutex to read the config
  reference. The checked-in benchmark measures the cost on CRuby and JRuby. A
  measured optimization may replace the publication mechanism, but it must keep
  one memory model across supported engines.
- The structural snapshot is thread-safe. User-supplied callbacks and other
  callable leaves must synchronize their own mutable state.
- `Retriable.config` is still a global. This ADR makes the global safe to read
  concurrently; it does not introduce per-thread, per-instance, or Ractor-safe
  configuration.
