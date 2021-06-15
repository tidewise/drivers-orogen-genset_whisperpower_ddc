# frozen_string_literal: true

using_task_library "genset_whisperpower_ddc"

describe OroGen.genset_whisperpower_ddc.Task do
    run_live

    attr_reader :task
    attr_reader :writer

    before do
        @task, @writer = iodrivers_base_prepare(
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

    it "outputs new generator state when receives generator state and model frame" do
        start_task(task, running_state_frame)

        sample = assert_driver_processes_frame(
            state_and_model_frame, task.generator_state_port
        )

        assert_in_delta(
            ((2 * Math::PI) / 60) * ((0x01 << 8) | 0x00),
            sample.rotation_speed
        )
        assert_in_delta(
            0.01 * ((0x03 << 8) | 0x02),
            sample.start_battery_voltage
        )
        assert_equal 0x0504, sample.alarms
        assert_equal 0x05, sample.start_signals
        assert_equal :STATUS_PRESENT, sample.generator_status
    end

    it "outputs new run time state when receives run time state frame" do
        start_task(task, running_state_frame)

        sample = assert_driver_processes_frame(
            run_time_state_frame, task.run_time_state_port
        )

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
        start_task(task, stopped_state_frame)

        syskit_write(task.control_cmd_port, true)
        assert_driver_sends_frame(run_time_state_frame, start_command_frame)
    end

    it "sends keep alive command if receives a valid frame when generator is running" do
        start_task(task, running_state_frame)

        syskit_write(task.control_cmd_port, true)
        assert_driver_sends_frame(run_time_state_frame, keep_alive_command_frame)
    end

    it "sends keep alive if receives start control command when generator is running" do
        start_task(task, running_state_frame)

        syskit_write(task.control_cmd_port, true)
        assert_driver_sends_frame(run_time_state_frame, keep_alive_command_frame)
    end

    it "sends the received stop control command if generator is running" do
        start_task(task, running_state_frame)

        syskit_write(task.control_cmd_port, false)
        assert_driver_sends_frame(run_time_state_frame, stop_command_frame)
    end

    it "does not send the received stop control command if generator is stopped" do
        start_task(task, stopped_state_frame)

        syskit_write(task.control_cmd_port, false)
        assert_driver_does_not_process_frame(run_time_state_frame, task.io_raw_out_port)
    end

    it "does not send command frame if has not received any command" do
        start_task(task, running_state_frame)

        assert_driver_does_not_process_frame(run_time_state_frame, task.io_raw_out_port)
    end

    it "does not send the received control command if has not received a valid frame" do
        start_task(task, stopped_state_frame)

        syskit_write(task.control_cmd_port, true)

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

        assert_driver_does_not_process_frame(frame, task.io_raw_out_port)

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

        assert_driver_does_not_process_frame(frame, task.io_raw_out_port)

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

        assert_driver_does_not_process_frame(frame, task.io_raw_out_port)
    end

    it "does not output new state if received frame is invalid" do
        start_task(task, stopped_state_frame)

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

    it "changes to running state if receives a running state frame while stopped" do
        start_task(task, stopped_state_frame)

        syskit_write(task.control_cmd_port, false)

        assert_driver_does_not_process_frame(run_time_state_frame, task.io_raw_out_port)
        assert_driver_sends_frame(running_state_frame, stop_command_frame)
    end

    it "changes to stopped state if receives a stopped state frame while running" do
        start_task(task, running_state_frame)

        syskit_write(task.control_cmd_port, true)

        assert_driver_sends_frame(run_time_state_frame, keep_alive_command_frame)
        assert_driver_sends_frame(stopped_state_frame, start_command_frame)
    end

    def iodrivers_base_prepare(model)
        task = syskit_deploy(model)
        syskit_start_execution_agents(task)
        writer = syskit_create_writer(task.io_raw_in_port)

        [task, writer]
    end

    def running_state_frame
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

    def stopped_state_frame
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

    def state_and_model_frame
        [
            0x81,
            0x00,
            0x88,
            0x00,
            0x02, # PACKET_GENERATOR_STATE_AND_MODEL
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x38
        ]
    end

    def run_time_state_frame
        [
            0x81,
            0x00,
            0x88,
            0x00,
            0x0E, # PACKET_RUN_TIME_STATE
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
            0x44
        ]
    end

    def start_command_frame
        [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x01, 0x00, 0x00, 0x00, # CONTROL_CMD_START
            0x01
        ]
    end

    def stop_command_frame
        [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x02, 0x00, 0x00, 0x00, # CONTROL_CMD_STOP
            0x02
        ]
    end

    def keep_alive_command_frame
        [
            0x88,
            0x00,
            0x81,
            0x00,
            0xF7, # PACKET_START_STOP
            0x03, 0x00, 0x00, 0x00, # CONTROL_CMD_KEEP_ALIVE
            0x03
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

    def assert_driver_sends_frame(received_frame, expected)
        expect_execution
            .join_all_waiting_work(false)
            .poll do
                writer.write Types.iodrivers_base.RawPacket.new(
                    time: Time.now, data: received_frame
                )
                sleep 0.1
            end
            .to do
                have_one_new_sample(task.io_raw_out_port)
                    .matching do |sample|
                        expected.each_with_index do |byte, i|
                            assert_equal byte, sample.data[i]
                        end
                    end
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
end
