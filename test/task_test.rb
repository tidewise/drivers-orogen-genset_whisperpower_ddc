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
        self.expect_execution_default_timeout = 30
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

    it "outputs_new_generator_state_when_receives_generator_state_and_model_frame" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x38
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        sample = expect_execution do
                     writer.write Types.iodrivers_base.RawPacket.new(
                         time: Time.now, data: received_frame
                     )
                 end
                 .to { have_one_new_sample task.generator_state_port }

        assert_equal (((2 * Math::PI) / 60) * ((0x01 << 8) | 0x00)).round(5),
                     sample.rotation_speed.round(5)
        assert_equal (0.01 * ((0x03 << 8) | 0x02)).round(5),
                     sample.start_battery_voltage.round(5)
        assert_equal 0x0504, sample.alarms
        assert_equal 0x05, sample.start_signals
        assert_equal :STATUS_PRESENT, sample.generator_status
    end

    it "outputs_new_run_time_state_when_receives_run_time_state_frame" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        sample = expect_execution do
                     writer.write Types.iodrivers_base.RawPacket.new(
                         time: Time.now, data: received_frame
                     )
                 end
                 .to { have_one_new_sample task.run_time_state_port }

        minutes = 0x00
        hours = (0x03 << 16) | (0x02 << 0x08) | 0x01
        assert_equal(
            Time.at((hours * 60 * 60) + (minutes * 60)),
            sample.total_run_time
        )

        minutes = 0x04
        hours = (0x07 << 16) | (0x06 << 8) | 0x05
        assert_equal(
            Time.at((hours * 60 * 60) + (minutes * 60)),
            sample.historical_run_time
        )
    end

    it "sends_the_received_start_control_command_if_generator_is_not_running" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, true)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        expected_frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x01, 0x00, 0x00, 0x00, # CONTROL_CMD_START
            0x01
        ]

        expected_frame.each_with_index do |byte, i|
            assert_equal byte, sent_frame.data[i]
        end
    end

    it "sends_keep_alive_control_command_if_generator_is_running" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        # First send start command to get it running
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, true)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        # Now that the generator is running, the component should send the keep_alive
        # command every time it receives a valid frame
        sent_frame = expect_execution do
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        expected_frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x03, 0x00, 0x00, 0x00, # CONTROL_CMD_KEEP_ALIVE
            0x03
        ]

        expected_frame.each_with_index do |byte, i|
            assert_equal byte, sent_frame.data[i]
        end
    end

    it "ignores_the_received_start_control_command_if_generator_is_running" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        # First send start command to get it running
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, true)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        # Now that the generator is running, try to send again the start command, but
        # verify that it is actually ignored and the keep_alive command is actually sent
        # to the generator
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, true)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        expected_frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x03, 0x00, 0x00, 0x00, # CONTROL_CMD_KEEP_ALIVE
            0x03
        ]

        expected_frame.each_with_index do |byte, i|
            assert_equal byte, sent_frame.data[i]
        end
    end

    it "sends_the_received_stop_control_command_if_generator_is_running" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        # First send start command to get it running
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, true)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        # Now that the generator is running, send the stop command
        sent_frame = expect_execution do
                         syskit_write(task.control_cmd_port, false)
                         writer.write Types.iodrivers_base.RawPacket.new(
                             time: Time.now, data: received_frame
                         )
                     end
                     .to do
                         have_one_new_sample task.run_time_state_port
                         have_one_new_sample task.io_raw_out_port
                     end

        expected_frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x02, 0x00, 0x00, 0x00, # CONTROL_CMD_STOP
            0x02
        ]

        expected_frame.each_with_index do |byte, i|
            assert_equal byte, sent_frame.data[i]
        end
    end

    it "does_not_send_the_received_stop_control_command_if_generator_is_not_running" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            syskit_write(task.control_cmd_port, false)
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
        .to do
            have_one_new_sample task.run_time_state_port
            have_no_new_sample task.io_raw_out_port
        end
    end

    it "does_not_send_control_command_frame_if_has_not_received_any_command" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.io_raw_out_port }
    end

    it "does_not_send_the_received_control_command_if_has_not_received_a_valid_frame" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        # Inverted addresses
        received_frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            syskit_write(task.control_cmd_port, true)
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
        .to do
            have_no_new_sample task.run_time_state_port
            have_no_new_sample task.io_raw_out_port
        end

        # Payload too short
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x44
        ]

        writer.write Types.iodrivers_base.RawPacket.new(
            time: Time.now, data: start_frame
        )

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            syskit_write(task.control_cmd_port, true)
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
        .to do
            have_no_new_sample task.run_time_state_port
            have_no_new_sample task.io_raw_out_port
        end

        # Wrong checksum
        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x45
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            syskit_write(task.control_cmd_port, true)
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
        .to do
            have_no_new_sample task.run_time_state_port
            have_no_new_sample task.io_raw_out_port
        end
    end

    it "does_not_output_new_state_if_received_source_target_or_command_is_unknown" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0xFF,
            0xFF,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.run_time_state_port }

        received_frame = [
            0x81,
            0x00,
            0xFF,
            0xFF,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.run_time_state_port }

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0xFF,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: received_frame
            )
        end
            .to { have_no_new_sample task.run_time_state_port }
    end

    it "does_not_output_new_state_when_reads_invalid_frame" do
        start_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x00, 0x08, 0x09,
            0x2B
        ]

        received_frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x08, 0x09,
            0x39 # invalid checksum
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

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
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x08, 0x09, 0x0A,
            0x42
        ]

        syskit_configure(task)
        start_writer = syskit_create_writer(task.io_raw_in_port)
        expect_execution { task.start! }
            .poll do
                start_writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
            end
            .to { emit task.start_event }

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
