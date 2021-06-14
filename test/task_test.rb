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

    it "outputs new generator state when receives generator state and model frame" do
        start_task(task, start_frame_running)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x38
        ]

        sample = assert_driver_processes_frame(frame, task.generator_state_port)

        assert_equal(
            (((2 * Math::PI) / 60) * ((0x01 << 8) | 0x00)).round(5),
            sample.rotation_speed.round(5)
        )
        assert_equal(
            (0.01 * ((0x03 << 8) | 0x02)).round(5),
            sample.start_battery_voltage.round(5)
        )
        assert_equal 0x0504, sample.alarms
        assert_equal 0x05, sample.start_signals
        assert_equal :STATUS_PRESENT, sample.generator_status
    end

    it "outputs new run time state when receives run time state frame" do
        start_task(task, start_frame_running)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        sample = assert_driver_processes_frame(frame, task.run_time_state_port)

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

    it "sends the received start control command if generator is not running" do
        start_task(task, start_frame_stopped)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        sent_frame = assert_driver_sends_command_frame(frame, command: true)

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

    it "sends keep alive command if receives a valid frame when generator is running" do
        start_task(task, start_frame_running)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        # no command is given to control_cmd port
        sent_frame = assert_driver_sends_command_frame(frame)

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

    it "sends keep alive if receives start control command when generator is running" do
        start_task(task, start_frame_running)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        sent_frame = assert_driver_sends_command_frame(frame, command: true)

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

    it "sends the received stop control command if generator is running" do
        start_task(task, start_frame_running)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        sent_frame = assert_driver_sends_command_frame(frame, command: false)

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

    it "does not send the received stop control command if generator is stopped" do
        start_task(task, start_frame_stopped)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        assert_driver_does_not_send_command_frame(frame, command: false)
    end

    it "does not send command frame if is stopped and has not received any command" do
        start_task(task, start_frame_stopped)

        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        assert_driver_does_not_send_command_frame(frame)
    end

    it "does not send the received control command if has not received a valid frame" do
        start_task(task, start_frame_stopped)

        # Inverted addresses
        frame = [
            0x88,
            0x00,
            0x81,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]

        assert_driver_does_not_send_command_frame(frame, command: true)

        # Payload too short
        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x44
        ]

        assert_driver_does_not_send_command_frame(frame, command: true)

        # Wrong checksum
        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x45
        ]

        assert_driver_does_not_send_command_frame(frame, command: true)
    end

    it "does not output new state if received frame is invalid" do
        start_task(task, start_frame_stopped)

        # Wrong target address
        frame = [
            0xFF,
            0xFF,
            0x88,
            0x00,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0xC1
        ]

        assert_driver_does_not_process_frame(frame, task.run_time_state_port)

        # Wrong source address
        frame = [
            0x81,
            0x00,
            0xFF,
            0xFF,
            0x0E,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0xBA
        ]

        assert_driver_does_not_process_frame(frame, task.run_time_state_port)

        # Unkown command
        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0xFF,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x35
        ]

        assert_driver_does_not_process_frame(frame, task.run_time_state_port)
        assert_driver_does_not_process_frame(frame, task.generator_state_port)

        # Invalid checksum
        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x08, 0x09,
            0xFF
        ]

        assert_driver_does_not_process_frame(frame, task.generator_state_port)

        # Frame too long
        frame = [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02,
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x00, 0x08, 0x09, 0x0A,
            0x42
        ]

        assert_driver_does_not_process_frame(frame, task.generator_state_port)
    end

    def iodrivers_base_prepare(model)
        task = syskit_deploy(model)
        syskit_start_execution_agents(task)
        reader = syskit_create_reader(task.io_raw_out_port, type: :buffer, size: 10)
        writer = syskit_create_writer(task.io_raw_in_port)

        [task, reader, writer]
    end

    def start_frame_running
        [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0xFF, 0x06, 0x07, 0x08, 0x09,
            0x32
        ]
    end

    def start_frame_stopped
        [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0x00, 0x06, 0x07, 0x08, 0x09,
            0x33
        ]
    end

    def start_task(task, start_frame)
        syskit_configure(task)
        expect_execution { task.start! }
            .join_all_waiting_work(false)
            .poll do
                writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: start_frame
                )
                sleep 0.1
            end
            .to { emit task.start_event }
    end

    def assert_driver_processes_frame(frame, port)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: frame
            )
        end
        .to do
            have_one_new_sample port
        end
    end

    def assert_driver_does_not_process_frame(frame, port)
        expect_execution do
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: frame
            )
        end
        .to do
            have_no_new_sample port
        end
    end

    def assert_driver_sends_command_frame(frame, command: nil)
        expect_execution do
            syskit_write(task.control_cmd_port, command) unless command.nil?
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: frame
            )
        end
        .to do
            have_one_new_sample task.io_raw_out_port
        end
    end

    def assert_driver_does_not_send_command_frame(frame, command: nil)
        expect_execution do
            syskit_write(task.control_cmd_port, command) unless command.nil?
            writer.write Types.iodrivers_base.RawPacket.new(
                time: Time.now, data: frame
            )
        end
        .to do
            have_no_new_sample task.io_raw_out_port
        end
    end
end
