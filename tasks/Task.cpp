/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "Task.hpp"
#include <iodrivers_base/ConfigureGuard.hpp>
#include <genset_whisperpower_ddc/VariableSpeed.hpp>
#include <genset_whisperpower_ddc/ControlCommand.hpp>
#include <fstream>

#include <base-logging/Logging.hpp>

using namespace std;
using namespace base;
using namespace genset_whisperpower_ddc;

/**
 * Exception thrown when the time spent by the component in startHook exceeds
 * m_startTimeout
 */
struct StartTimeoutError : public std::runtime_error {
    using std::runtime_error::runtime_error;
};

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

    std::cout << "RUNNING: " << endl;

    try {
        m_running = isRunning();
    }
    catch(const StartTimeoutError& e) {
        LOG_ERROR_S << e.what() << std::endl;
        exception(START_TIMEOUT);
        return false;
    }

    return true;
}

void Task::updateHook()
{
    TaskBase::updateHook();
}

void Task::processIO()
{
    Frame frame;

    try
    {
        frame = m_driver->readFrame();
    }
    catch(const variable_speed::WrongSize& e)
    {
        return;
    }
    catch(const variable_speed::InvalidChecksum& e)
    {
        return;
    }

    /**
     * Generator starts running when it receives the start command. After that, keep sending the keep_alive command to the generator
     * until receive stop control command on the input port.
     * Only send control command after receiving a valid frame coming from the generator.
     * If received frame is valid but comes from another source or has a different target, just ignore it and
     * don't send control command
     */
    if (frame.targetID != variable_speed::PANELS_ADDRESS || frame.sourceID != variable_speed::DDC_CONTROLLER_ADDRESS) {
        return;
    }

    auto now = Time::now();

    if (frame.command == variable_speed::PACKET_GENERATOR_STATE_AND_MODEL){
        GeneratorState currentState = m_driver->parseGeneratorStateAndModel(frame.payload, now).first;
        m_running = isRunning(currentState);
        _generator_state.write(currentState);
    }
    else if (frame.command == variable_speed::PACKET_RUN_TIME_STATE) {
        _run_time_state.write(m_driver->parseRunTimeState(frame.payload, now));
    }

    processStartStopCommand();
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

void Task::processStartStopCommand()
{
    bool cmd;
    if (_control_cmd.read(cmd) == RTT::NoData) {
        return;
    }

    if (m_running && !cmd) {
        m_driver->sendControlCommand(CONTROL_CMD_STOP);
        return;
    }

    if (!m_running && cmd) {
        m_driver->sendControlCommand(CONTROL_CMD_START);
        return;
    }

    if (m_running) {
        m_driver->sendControlCommand(CONTROL_CMD_KEEP_ALIVE);
    }
}

bool Task::isRunning(GeneratorState state){
    return state.start_signals & GeneratorState::RUN_SIGNAL;
}

bool Task::isRunning() {
    base::Time deadline = base::Time::now() + m_startTimeout;

    while (true) {
        if (base::Time::now() >= deadline) {
            throw StartTimeoutError(
                "timed out waiting for a GENERATOR_STATE_AND_MODEL message "
                "from the genset"
            );
        }

        try {
            Frame frame = m_driver->readFrame();
            if (frame.targetID == variable_speed::PANELS_ADDRESS &&
                frame.sourceID == variable_speed::DDC_CONTROLLER_ADDRESS &&
                frame.command == variable_speed::PACKET_GENERATOR_STATE_AND_MODEL) {

                GeneratorState currentState = m_driver->parseGeneratorStateAndModel(
                    frame.payload, base::Time::now()
                ).first;
                return currentState.start_signals & GeneratorState::RUN_SIGNAL;
            }
        }
        catch(const variable_speed::WrongSize& e) { }
        catch(const variable_speed::InvalidChecksum& e) { }
        // iodrivers_base may throw this error when receiving a SIGINT, but it
        // can be ignored
        catch(const iodrivers_base::UnixError& e) { }
    }

    // Never reached
}
