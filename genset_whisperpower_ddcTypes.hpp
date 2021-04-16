#ifndef genset_whisperpower_ddc_TYPES_HPP
#define genset_whisperpower_ddc_TYPES_HPP

#include <base/Time.hpp>
#include <genset_whisperpower_ddc/GeneratorStatus.hpp>

/* If you need to define types specific to your oroGen components, define them
 * here. Required headers must be included explicitly
 *
 * However, it is common that you will only import types from your library, in
 * which case you do not need this file
 */

namespace genset_whisperpower_ddc {
    struct GeneratorState {
        base::Time time;

        int rpm;
        int udc_start_battery;
        bool overall_alarm;
        bool engine_temperature_alarm;
        bool pm_voltage_alarm;
        bool oil_pressure_alarm;
        bool exhaust_temperature_alarm;
        bool uac1_alarm;
        bool iac1_alarm;
        bool oil_pressure_high_alarm;
        bool low_start_battery_voltage_alarm;
        bool start_failure;
        bool run_signal;
        bool start_by_operation_unit;
        bool model_detection_50hz;
        bool model_detection_60hz;
        bool model_detection_3_phase;
        bool model_detection_mobile;
        GeneratorStatus generator_status;
        int generator_type;
    };

    struct RuntimeState {
        base::Time time;
        
        int total_runtime_minutes; // Total run time to be reset after maintenance
        int total_runtime_hours;
        int historical_runtime_minutes;
        int historical_runtime_hours;
    };
}

#endif

