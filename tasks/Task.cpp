/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "Task.hpp"
#include <genset_whisperpower_ddc/VariableSpeedMaster.hpp>
#include <bits/stdc++.h>

using namespace genset_whisperpower_ddc;

Task::Task(std::string const& name)
    : TaskBase(name)
{
}

Task::~Task()
{
}



/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See Task.hpp for more detailed
// documentation about them.

bool Task::configureHook()
{       
    unique_ptr<VariableSpeedMaster> driver(new VariableSpeedMaster());

    // Un-configure the device driver if the configure fails.
    // You MUST call guard.commit() once the driver is fully
    // functional (usually before the configureHook's "return true;"
    iodrivers_base::ConfigureGuard guard(this);
    if (!_io_port.get().empty())
        driver->openURI(_io_port.get());
    setDriver(driver.get());

    // This is MANDATORY and MUST be called after the setDriver but before you do
    // anything with the driver
    if (! TaskBase::configureHook())
        return false;

    m_driver = move(driver);
    
    guard.commit();
    return true;
}
bool Task::startHook()
{
    if (! TaskBase::startHook())
        return false;
    return true;
}
void Task::updateHook()
{
    auto now = Time::now();
    Frame frame = m_driver->readFrame();

    if (frame.targetID == 0x0081 && frame.sourceID == 0x0088) {
        if (frame.command == 2){
            GeneratorState generator_state;
            generator_state.time = now;
            generator_state.rpm = (frame.payload[1] << 8) | frame.payload[0];
            stgenerator_state.udc_start_battery = (frame.payload[3] << 8) | frame.payload[2];
            std::bitset<8> statusA(frame.payload[4]);
            generator_state.overall_alarm = statusA[0];
            generator_state.engine_temperature_alarm = statusA[1];
            generator_state.pm_voltage_alarm = statusA[2];
            generator_state.oil_pressure_alarm = statusA[3];
            generator_state.exhaust_temperature_alarm = statusA[4];
            generator_state.uac1_alarm = statusA[5];
            generator_state.iac1_alarm = statusA[6];
            generator_state.oil_pressure_high_alarm = statusA[7];
            std::bitset<8> statusB(frame.payload[5]);
            generator_state.low_start_battery_voltage_alarm = statusB[2];
            generator_state.start_failure = statusB[4];
            generator_state.run_signal = statusB[5];
            generator_state.start_by_operation_unit = statusB[7];
            std::bitset<8> statusC(frame.payload[6]);
            generator_state.model_detection_50hz = statusC[2];
            generator_state.model_detection_60hz = statusC[3];
            generator_state.model_detection_3_phase = statusC[4];
            generator_state.model_detection_mobile = statusC[5];
            if (frame.payload[7] < 0x0E){
                generator_state.generator_status = static_cast<GeneratorStatus>(frame.payload[7]);
            }
            else{
                generator_state.generator_status = STATUS_UNKNOWN;
            }
            generator_state.generator_type = frame.payload[8];

            _generator_state.write(generator_state);

            while (_control_cmd.read(m_control_cmd) == RTT::NewData) {
                sendControlCommand(m_control_cmd);
            }
        }
        else if (frame.command == 14) {
            RunTimeState run_time_state;
            run_time_state.time = now;
            run_time_state.total_runtime_minutes = frame.payload[0];
            run_time_state.total_runtime_hours = (frame.payload[3] << 16) | (frame.payload[2] << 8) | frame.payload[1];
            run_time_state.historical_runtime_minutes = frame.payload[4];
            run_time_state.historical_runtime_hours = (frame.payload[7] << 16) | (frame.payload[6] << 8) | frame.payload[5];

            _run_time_state.write(run_time_state);

            while (_control_cmd.read(m_control_cmd) == RTT::NewData) {
                sendControlCommand(m_control_cmd);
            }
        }
    }

    TaskBase::updateHook();
}
void Task::errorHook()
{
    TaskBase::errorHook();
}
void Task::stopHook()
{
    TaskBase::stopHook();
}
void Task::cleanupHook()
{
    TaskBase::cleanupHook();
    // Delete the driver AFTER calling TaskBase::configureHook, as the latter
    // detaches the driver from the oroGen I/O
    m_driver.release();
}
