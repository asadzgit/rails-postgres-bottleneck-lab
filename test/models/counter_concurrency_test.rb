require "test_helper"

class CounterConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    LabCounter.upsert({ id: 1, value: 0 })
  end

  teardown do
    LabCounter.delete_all
  end

  test "increments execute even when the Active Record query cache is enabled" do
    ActiveRecord::Base.cache do
      2.times { Lab::CounterIncrement.new(mode: "short", work_ms: 1, lock_timeout_ms: 1000).call }
    end
    assert_equal 2, LabCounter.find(1).value
  end

  test "concurrent short transactions do not lose increments" do
    threads = 3.times.map do
      Thread.new do
        4.times { Lab::CounterIncrement.new(mode: "short", work_ms: 1, lock_timeout_ms: 1000).call }
      end
    end
    threads.each(&:value)
    assert_equal 12, LabCounter.find(1).value
  end

  test "a real row blocker times out a waiter and rollback leaves the counter unchanged" do
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.transaction do
          connection.execute("SELECT value FROM lab_counters WHERE id=1 FOR UPDATE")
          ready << true
          release.pop
        end
      end
    end
    begin
      ready.pop
      assert_raises(ActiveRecord::LockWaitTimeout) do
        Lab::CounterIncrement.new(mode: "long", work_ms: 1, lock_timeout_ms: 20).call
      end
    ensure
      release << true
      holder.value
    end
    assert_equal 0, LabCounter.find(1).value
    Lab::CounterIncrement.new(mode: "short", work_ms: 1, lock_timeout_ms: 1000).call
    assert_equal 1, LabCounter.find(1).value
  end
end
