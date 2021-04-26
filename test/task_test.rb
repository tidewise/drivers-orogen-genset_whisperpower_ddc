# frozen_string_literal: true

using_task_library "genset_whisperpower_ddc"

describe OroGen.genset_whisperpower_ddc.Task do
    run_live

    attr_reader :task
    attr_reader :reader
    attr_reader :writer

    before do
        @task, @reader, @writer = iodrivers_base_prepare(
            OroGen.genset_whisperpower_ddc.Task
                  .deployed_as("genset_whisperpower_ddc")
        )
        @task.properties.io_read_timeout = Time.at(2)
    end

    def iodrivers_base_prepare(model)
        task = syskit_deploy(model)
        syskit_start_execution_agents(task)
        syskit_create_reader(task.io_raw_out_port, type: :buffer, size: 10)
        syskit_create_writer(task.io_raw_in_port)
        writer = task.io_raw_in_port.writer
        reader = task.io_raw_out_port.reader

        [task, reader, writer]
    end

    it "outputs_new_generator_state_when_receives_command_2_frame" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x38
        ]
        now = Time.now
        syskit_wait_ready(writer, component: task)
        sample = expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: now, data: received_frame) }
                 .to { have_one_new_sample task.generator_state_port }

        # assert_equal now, sample.time
        assert_equal (1 << 8) | 0, sample.rpm
        assert_equal (3 << 8) | 2, sample.udc_start_battery
        assert_equal 4, sample.statusA
        assert_equal 5, sample.statusB
        assert_equal 6, sample.statusC
        assert_equal :STATUS_PRESENT, sample.generator_status
        assert_equal 8, sample.generator_type
    end

    it "outputs_runtime_state_when_receives_command_14_frame" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]
        now = Time.now
        syskit_wait_ready(writer, component: task)
        sample = expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: now, data: received_frame) }
                 .to { have_one_new_sample task.runtime_state_port }

        # assert_equal now, sample.time
        assert_equal 0, sample.total_runtime_minutes
        assert_equal (3 << 16) | (2 << 8) | 1, sample.total_runtime_hours
        assert_equal 4, sample.historical_runtime_minutes
        assert_equal (7 << 16) | (6 << 8) | 5, sample.historical_runtime_hours
    end

    it "sends_the_received_control_command" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        syskit_write(task.control_cmd_port, :CONTROL_CMD_STOP)
        sent_frame = expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame) }
                     .to do
                         have_one_new_sample task.runtime_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        expected_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0xF7,
            0x02, 0x00, 0x00, 0x00,
            0x02
        ]

        expected_frame.each_with_index do |byte, i|
            assert_equal byte, sent_frame.data[i]
        end
    end

    it "does_not_send_frame_if_has_not_received_new_command" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame) }
            .to { have_no_new_sample task.io_raw_out_port }
    end

    it "does_not_output_new_state_if_received_source_target_or_command_is_unknown" do
        received_frame = [
            0xFF,
            0xFF,
            0x88,
            0x00,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame) }
            .to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            0x81,
            0x00,
            0xFF,
            0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame) }
            .to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0xFF,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution { writer.write Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame) }
            .to { have_no_new_sample task.runtime_state_port }
    end
end
