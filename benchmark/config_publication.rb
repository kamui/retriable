# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "rbconfig"
require "retriable"

RUN_SECONDS = Float(ENV.fetch("RETRIABLE_BENCH_SECONDS", "1.0"))
THREAD_COUNTS = ENV.fetch("RETRIABLE_BENCH_THREADS", "1,2,4,8")
                   .split(",")
                   .map { |value| Integer(value, 10) }
                   .uniq
                   .freeze
BATCH_SIZE = 100

raise ArgumentError, "RETRIABLE_BENCH_SECONDS must be positive" unless RUN_SECONDS.positive?
raise ArgumentError, "RETRIABLE_BENCH_THREADS must contain positive integers" unless THREAD_COUNTS.all?(&:positive?)

SnapshotHolder = Struct.new(:value)
snapshot_holder = SnapshotHolder.new(Retriable.config)

BENCHMARK_CASES = {
  "plain_snapshot_read" => -> { snapshot_holder.value },
  "published_config_read" => -> { Retriable.config },
  "successful_retriable" => -> { Retriable.retriable { nil } }
}.freeze

def monotonic_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def measure(operation, thread_count)
  ready = Queue.new
  start = Queue.new
  threads = Array.new(thread_count) do
    Thread.new do
      ready << true
      start.pop
      count = 0
      deadline = monotonic_time + RUN_SECONDS

      loop do
        BATCH_SIZE.times { operation.call }
        count += BATCH_SIZE
        break if monotonic_time >= deadline
      end

      count
    end
  end

  thread_count.times { ready.pop }
  started_at = monotonic_time
  thread_count.times { start << true }
  operation_count = threads.sum(&:value)
  elapsed = monotonic_time - started_at

  operation_count / elapsed
end

BENCHMARK_CASES.each_value do |operation|
  5_000.times { operation.call }
end

puts "ruby=#{RUBY_DESCRIPTION}"
puts "engine=#{RUBY_ENGINE}"
puts "host_cpu=#{RbConfig::CONFIG.fetch("host_cpu")}"
puts "seconds_per_case=#{RUN_SECONDS}"
puts "case,threads,operations_per_second"

BENCHMARK_CASES.each do |name, operation|
  THREAD_COUNTS.each do |thread_count|
    operations_per_second = measure(operation, thread_count)
    puts format(
      "%<name>s,%<threads>d,%<operations>d",
      name: name, threads: thread_count, operations: operations_per_second.round,
    )
  end
end
