require 'test_helper'

class TestMemcachedSafety < ActiveSupport::TestCase
  setup do
    @cache = MemcachedStore::MemcachedSafety.new(["localhost:21211"])
    @entry = ActiveSupport::Cache::Entry.new(omg: "ponies")
  end

  test "exist? absorbs non-fatal exceptions" do
    expect_nonfatal(:exist_without_rescue?)
    @cache.exist?("a-key")
  end

  test "exist? raises fatal exceptions" do
    expect_fatal(:exist_without_rescue?)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.exist?("a-key")
    end
  end

  test "cas absorbs non-fatal exceptions" do
    expect_nonfatal(:cas_without_rescue)
    @cache.cas("a-key") { 1 }
  end

  test "cas raises fatal exceptions" do
    expect_fatal(:cas_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.cas("a-key") { 1 }
    end
  end

  test "get_multi absorbs non-fatal exceptions" do
    expect_nonfatal(:get_multi_without_rescue)
    @cache.get_multi(["a-key"])
  end

  test "get_multi raises fatal exceptions" do
    expect_fatal(:get_multi_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.get_multi(["a-key"])
    end
  end

  test "set absorbs non-fatal exceptions" do
    expect_nonfatal(:set_without_rescue)
    @cache.set("a-key", @entry)
  end

  test "set raises fatal exceptions" do
    expect_fatal(:set_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.set("a-key", @entry)
    end
  end

  test "add absorbs non-fatal exceptions" do
    expect_nonfatal(:add_without_rescue)
    @cache.add("a-key", "val")
  end

  test "add raises fatal exceptions" do
    expect_fatal(:add_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.add("a-key", "val")
    end
  end

  test "delete absorbs non-fatal exceptions" do
    expect_nonfatal(:delete_without_rescue)
    @cache.delete("a-key")
  end

  test "delete raises fatal exceptions" do
    expect_fatal(:delete_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.delete("a-key")
    end
  end

  test "incr absorbs non-fatal exceptions" do
    expect_nonfatal(:incr_without_rescue)
    @cache.incr("a-key")
  end

  test "incr raises fatal exceptions" do
    expect_fatal(:incr_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.incr("a-key")
    end
  end

  test "decr absorbs non-fatal exceptions" do
    expect_nonfatal(:decr_without_rescue)
    @cache.decr("a-key")
  end

  test "decr raises fatal exceptions" do
    expect_fatal(:decr_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.decr("a-key")
    end
  end

  test "append absorbs non-fatal exceptions" do
    expect_nonfatal(:append_without_rescue)
    @cache.append("a-key", "other")
  end

  test "append raises fatal exceptions" do
    expect_fatal(:append_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.append("a-key", "other")
    end
  end

  test "prepend absorbs non-fatal exceptions" do
    expect_nonfatal(:prepend_without_rescue)
    @cache.prepend("a-key", "other")
  end

  test "prepend raises fatal exceptions" do
    expect_fatal(:prepend_without_rescue)
    assert_raises(Memcached::AKeyLengthOfZeroWasProvided) do
      @cache.prepend("a-key", "other")
    end
  end

  test "logger defaults to rails logger" do
    assert_equal Rails.logger, @cache.logger
  end

  private

  def expect_nonfatal(sym)
    MemcachedStore::MemcachedSafety.any_instance.expects(sym).raises(Memcached::ServerIsMarkedDead)
  end

  def expect_fatal(sym)
    MemcachedStore::MemcachedSafety.any_instance.expects(sym).raises(Memcached::AKeyLengthOfZeroWasProvided)
  end
end
