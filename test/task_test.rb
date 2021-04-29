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

    after do
        if task&.running?
            expect_execution { task.stop! }
                .join_all_waiting_work(false)
                .to { emit task.stop_event }
        end
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
            0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9,
            0x38
        ]

        syskit_wait_ready(writer, component: task)
        sample = expect_execution do
                     writer.write Types.iodrivers_base.RawPacket.new(
                         time: Time.now, data: received_frame
                     )
                 end
                 .to { have_one_new_sample task.generator_state_port }

        assert_equal (0x01 << 8) | 0x00, sample.rpm
        assert_equal (0x03 << 8) | 0x02, sample.udc_start_battery
        assert_equal 0x060504, sample.status
        assert_equal :STATUS_PRESENT, sample.generator_status
        assert_equal 0x08, sample.generator_type
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

        syskit_wait_ready(writer, component: task)
        sample = expect_execution do
                     writer.write Types.iodrivers_base.RawPacket.new(
                         time: Time.now, data: received_frame
                     )
                 end
                 .to { have_one_new_sample task.runtime_state_port }

        minutes = 0x00
        hours = (0x03 << 16) | (0x02 << 0x08) | 0x01
        #assert_equal Types.base.Time.new((hours * 60 * 60 * 1_000_000) + (minutes * 60 * 1_000_000)), sample.total_runtime

        minutes = 0x04
        hours = (0x07 << 16) | (0x06 << 8) | 0x05
        #assert_equal Types.base.Time.new((hours * 60 * 60 * 1_000_000) + (minutes * 60 * 1_000_000)), sample.historical_runtime
    end

    it "sends_the_received_control_command" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, :CONTROL_CMD_STOP)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
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
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.io_raw_out_port }
    end

    it "does_not_output_new_state_if_received_source_target_or_command_is_unknown" do
        received_frame = [
            0xFF,
            0xFF,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            0x81,
            0x00,
            0xFF,
            0xFF,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0xFF,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.runtime_state_port }
    end

    it "does_nothing_when_reads_invalid_frame" do
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x39 # invalid checksum
        ]

        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to do
                have_no_new_sample task.generator_state_port
            end

        # frame too long
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
            0x42
        ]
        syskit_wait_ready(writer, component: task)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to do
                have_no_new_sample task.generator_state_port
            end
    end
end
