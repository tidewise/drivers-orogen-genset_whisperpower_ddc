/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "Task.hpp"
#include <iodrivers_base/ConfigureGuard.hpp>
#include <bits/stdc++.h>

using namespace std;
using namespace base;
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
            _generator_state.write(m_driver->parseGeneratorState(frame.payload, now));

            while (_control_cmd.read(m_control_cmd) == RTT::NewData) {
                m_driver->sendControlCommand(m_control_cmd);
            }
        }
        else if (frame.command == 14) {
            _runtime_state.write(m_driver->parseRuntimeState(frame.payload, now));

            while (_control_cmd.read(m_control_cmd) == RTT::NewData) {
                m_driver->sendControlCommand(m_control_cmd);
            }
        }
    }

    TaskBase::updateHook();
}
void Task::processIO()
{
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

void Task::exceptionHook()
{
    TaskBase::exceptionHook();
}