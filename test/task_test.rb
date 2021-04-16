# frozen_string_literal: true

using_task_library "genset_whisperpower_ddc"

describe OroGen.genset_whisperpower_ddc.Task do
    run_live

    attr_reader :task

    before do
        @task = iodrivers_base_prepare(
            OroGen.genset_whisperpower_ddc.Task
                  .deployed_as("genset_whisperpower_ddc")
        )
    end

    def iodrivers_base_prepare(model)
        task = syskit_deploy(model)
        syskit_configure_and_start(task)

        task
    end

    it "outputs_new_generator_state_when_receives_command_2_frame" do
        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0x02,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x38
        ]
        now = Time.now
        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: now, data: received_frame)
        )

        sample = expect_execution.to { have_one_new_sample task.generator_state_port }

        expected_state = GeneratorState.new(
            time: now,
            rpm: (1 << 8) | 0,
            udc_start_battery: (3 << 8) | 2,

            overall_alarm: 4[0],
            engine_temperature_alarm: 4[1],
            pm_voltage_alarm: 4[2],
            oil_pressure_alarm: 4[3],
            exhaust_temperature_alarm: 4[4],
            uac1_alarm: 4[5],
            iac1_alarm: 4[6],
            oil_pressure_high_alarm: 4[7],

            low_start_battery_voltage_alarm: 5[2],
            start_failure: 5[4],
            run_signal: 5[5],
            start_by_operation_unit: 5[7],

            model_detection_50hz: 6[2],
            model_detection_60hz: 6[3],
            model_detection_3_phase: 6[4],
            model_detection_mobile: 6[5],

            generator_status: :STATUS_PRESENT,
            generator_type: 8
        )

        assert_equal expected_state, sample.value
    end

    it "outputs_runtime_state_when_receives_command_14_frame" do
        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]
        now = Time.now
        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: now, data: received_frame)
        )

        sample = expect_execution.to { have_one_new_sample task.runtime_state_port }

        expected_state = RuntimeState.new(
            time: now,
            total_runtime_minutes: 0,
            total_runtime_hours: (3 << 16) | (2 << 8) | 1,
            historical_runtime_minutes: 4,
            historical_runtime_hours: (7 << 16) | (6 << 8) | 5
        )

        assert_equal expected_state, sample.value
    end

    it "sends_the_received_control_command" do
        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_write(task.control_cmd_port, :CONTROL_CMD_STOP)

        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame)
        )

        sent_frame = expect_execution.to { have_one_new_sample task.io_raw_out_port }

        expected_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0xF7,
            0x02, 0x00, 0x00, 0x00,
            0x02
        ]

        assert_equal expected_frame, sent_frame.value
    end

    it "does_not_send_frame_if_has_not_received_new_command" do
        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]

        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: Time.now, data: received_frame)
        )

        expect_execution.to { have_no_new_sample task.io_raw_out_port }
    end

    it "ignores_frame_if_source_target_or_command_is_unknown" do
        received_frame = [
            0xFF,
            0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]
        now = Time.now
        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: now, data: received_frame)
        )

        expect_execution.to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            0xFF,
            0xFF,
            0x0E,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]
        now = Time.now
        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: now, data: received_frame)
        )

        expect_execution.to { have_no_new_sample task.runtime_state_port }

        received_frame = [
            variable_speed::TARGET_ADDRESS & 0xFF,
            (variable_speed::TARGET_ADDRESS >> 8) & 0xFF,
            variable_speed::SOURCE_ADDRESS & 0xFF,
            (variable_speed::SOURCE_ADDRESS >> 8) & 0xFF,
            0xFF,
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
            0x44
        ]
        now = Time.now
        syskit_write(
            task.io_raw_in_port,
            Types.iodrivers_base.RawPacket.new(time: now, data: received_frame)
        )

        expect_execution.to { have_no_new_sample task.runtime_state_port }
    end
end
