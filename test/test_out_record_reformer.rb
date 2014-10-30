require_relative 'helper'
require 'rr'
require 'timecop'
require 'fluent/plugin/out_record_reformer'

Fluent::Test.setup

class RecordReformerOutputTest < Test::Unit::TestCase
  setup do
    @hostname = Socket.gethostname.chomp
    @tag = 'test.tag'
    @tag_parts = @tag.split('.')
    @time = Time.local(1,2,3,4,5,2010,nil,nil,nil,nil)
    Timecop.freeze(@time)
  end

  teardown do
    Timecop.return
  end

  def create_driver(conf)
    Fluent::Test::OutputTestDriver.new(Fluent::RecordReformerOutput, @tag).configure(conf)
  end

  def emit(config, msgs = [''])
    d = create_driver(config)
    msgs.each do |msg|
      d.run { d.emit({'eventType0' => 'bar', 'message' => msg}, @time) }
    end

    @instance = d.instance
    d.emits
  end

  CONFIG = %[
    tag reformed.${tag}

    hostname ${hostname}
    input_tag ${tag}
    time ${time.to_s}
    message ${hostname} ${tag_parts.last} ${URI.escape(message)}
  ]

  sub_test_case 'configure' do
    test 'typical usage' do
      assert_nothing_raised do
        create_driver(CONFIG)
      end
    end

    test "tag is not specified" do
      assert_raise(Fluent::ConfigError) do
        create_driver('')
      end
    end

    test "keep_keys must be specified together with renew_record true" do
      assert_raise(Fluent::ConfigError) do
        create_driver(%[keep_keys a])
      end
    end
  end

  sub_test_case "test options" do
    test 'typical usage' do
      msgs = ['1', '2']
      emits = emit(CONFIG, msgs)
      assert_equal 2, emits.size
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal('bar', record['eventType0'])
        assert_equal(@hostname, record['hostname'])
        assert_equal(@tag, record['input_tag'])
        assert_equal(@time.to_s, record['time'])
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", record['message'])
      end
    end

    test '(obsolete) output_tag' do
      config = %[output_tag reformed.${tag}]
      msgs = ['1']
      emits = emit(config, msgs)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
      end
    end

    test 'record directive' do
      config = %[
        tag reformed.${tag}

        <record>
          hostname ${hostname}
          tag ${tag}
          time ${time.to_s}
          message ${hostname} ${tag_parts.last} ${message}
        </record>
      ]
      msgs = ['1', '2']
      emits = emit(config, msgs)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal('bar', record['eventType0'])
        assert_equal(@hostname, record['hostname'])
        assert_equal(@tag, record['tag'])
        assert_equal(@time.to_s, record['time'])
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", record['message'])
      end
    end

    test 'remove_keys' do
      config = CONFIG + %[remove_keys eventType0,message]
      emits = emit(config)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal(nil, record['eventType0'])
        assert_equal(@hostname, record['hostname'])
        assert_equal(@tag, record['input_tag'])
        assert_equal(@time.to_s, record['time'])
        assert_equal(nil, record['message'])
      end
    end

    test 'renew_record' do
      config = CONFIG + %[renew_record true]
      msgs = ['1', '2']
      emits = emit(config, msgs)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal(nil, record['eventType0'])
        assert_equal(@hostname, record['hostname'])
        assert_equal(@tag, record['input_tag'])
        assert_equal(@time.to_s, record['time'])
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", record['message'])
      end
    end

    test 'keep_keys' do
      config = %[tag reformed.${tag}\nrenew_record true\nkeep_keys eventType0,message]
      msgs = ['1', '2']
      emits = emit(config, msgs)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal('bar', record['eventType0'])
        assert_equal(msgs[i], record['message'])
      end
    end

    test 'enable_ruby no' do
      config = %[
        tag reformed.${tag}
        enable_ruby no
        <record>
          message ${hostname} ${tag_parts.last} ${URI.encode(message)}
        </record>
      ]
      msgs = ['1', '2']
      emits = emit(config, msgs)
      emits.each_with_index do |(tag, time, record), i|
        assert_equal("reformed.#{@tag}", tag)
        assert_equal("#{@hostname} ${tag_parts.last} ${URI.encode(message)}", record['message'])
      end
    end
  end

  sub_test_case 'test placeholders' do
    %w[yes no].each do |enable_ruby|
      test "hostname with enble_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${hostname}
          </record>
        ]
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(@hostname, record['message'])
        end
      end

      test "tag with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${tag}
          </record>
        ]
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(@tag, record['message'])
        end
      end

      test "tag_parts with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${tag_parts[0]} ${tag_parts[-1]}
          </record>
        ]
        expected = "#{@tag.split('.').first} #{@tag.split('.').last}"
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(expected, record['message'])
        end
      end

      test "(obsolete) tags with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${tags[0]} ${tags[-1]}
          </record>
        ]
        expected = "#{@tag.split('.').first} #{@tag.split('.').last}"
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(expected, record['message'])
        end
      end

      test "${tag_prefix[N]} and ${tag_suffix[N]} with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${tag_prefix[1]} ${tag_prefix[-2]} ${tag_suffix[2]} ${tag_suffix[-3]}
          </record>
        ]
        @tag = 'prefix.test.tag.suffix'
        expected = "prefix.test prefix.test.tag tag.suffix test.tag.suffix"
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(expected, record['message'])
        end
      end

      test "time with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          <record>
            message ${time}
          </record>
        ]
        emits = emit(config)
        emits.each do |(tag, time, record)|
          assert_equal(@time.to_s, record['message'])
        end
      end

      test "record keys with enable_ruby #{enable_ruby}" do
        config = %[
          tag tag
          enable_ruby #{enable_ruby}
          remove_keys eventType0
          <record>
            message bar ${message}
            eventtype ${eventType0}
          </record>
        ]
        msgs = ['1', '2']
        emits = emit(config, msgs)
        emits.each_with_index do |(tag, time, record), i|
          assert_equal(nil, record['eventType0'])
          assert_equal("bar", record['eventtype'])
          assert_equal("bar #{msgs[i]}", record['message'])
        end
      end
    end

    test 'unknown placeholder (enable_ruby no)' do
      config = %[
        tag tag
        enable_ruby no
        <record>
          message ${unknown}
        </record>
      ]
      d = create_driver(config)
      mock(d.instance.log).warn("record_reformer: unknown placeholder `${unknown}` found")
      d.run { d.emit({}, @time) }
      assert_equal 1, d.emits.size
    end

    test 'failed to expand record field (enable_ruby yes)' do
      config = %[
        tag tag
        enable_ruby yes
        <record>
          message ${unknown['bar']}
        </record>
      ]
      d = create_driver(config)
      mock(d.instance.log).warn("record_reformer: failed to expand `${unknown['bar']}`", anything)
      d.run { d.emit({}, @time) }
      # emit, but nil value
      assert_equal 1, d.emits.size
      d.emits.each do |(tag, time, record)|
        assert_equal(nil, record['message'])
      end
    end

    test 'failed to expand tag (enable_ruby yes)' do
      config = %[
        tag ${unknown['bar']}
        enable_ruby yes
      ]
      d = create_driver(config)
      mock(d.instance.log).warn("record_reformer: failed to expand `${unknown['bar']}`", anything)
      d.run { d.emit({}, @time) }
      # nil tag message should not be emitted
      assert_equal 0, d.emits.size
    end
  end
end
