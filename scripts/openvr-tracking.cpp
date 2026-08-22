#include <openvr.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

namespace {

const char *class_name(vr::ETrackedDeviceClass device_class)
{
    switch (device_class) {
    case vr::TrackedDeviceClass_HMD:
        return "HMD";
    case vr::TrackedDeviceClass_Controller:
        return "controller";
    case vr::TrackedDeviceClass_GenericTracker:
        return "tracker";
    case vr::TrackedDeviceClass_TrackingReference:
        return "base";
    case vr::TrackedDeviceClass_DisplayRedirect:
        return "display";
    default:
        return "device";
    }
}

const char *tracking_result_name(vr::ETrackingResult result)
{
    switch (result) {
    case vr::TrackingResult_Uninitialized:
        return "uninitialized";
    case vr::TrackingResult_Calibrating_InProgress:
        return "calibrating";
    case vr::TrackingResult_Calibrating_OutOfRange:
        return "calibrating/out-of-range";
    case vr::TrackingResult_Running_OK:
        return "running/OK";
    case vr::TrackingResult_Running_OutOfRange:
        return "running/out-of-range";
    case vr::TrackingResult_Fallback_RotationOnly:
        return "rotation-only";
    default:
        return "unknown";
    }
}

std::string string_property(vr::IVRSystem *system,
                            vr::TrackedDeviceIndex_t device,
                            vr::ETrackedDeviceProperty property)
{
    vr::ETrackedPropertyError error = vr::TrackedProp_Success;
    const uint32_t size = system->GetStringTrackedDeviceProperty(device, property, nullptr, 0, &error);
    if (size == 0 || (error != vr::TrackedProp_Success && error != vr::TrackedProp_BufferTooSmall)) {
        return {};
    }

    std::string value(size, '\0');
    error = vr::TrackedProp_Success;
    system->GetStringTrackedDeviceProperty(device, property, value.data(), size, &error);
    if (error != vr::TrackedProp_Success) {
        return {};
    }
    if (!value.empty() && value.back() == '\0') {
        value.pop_back();
    }
    return value;
}

struct DeviceStats {
    bool seen = false;
    bool relevant = false;
    std::string serial;
    vr::ETrackedDeviceClass device_class = vr::TrackedDeviceClass_Invalid;
    unsigned samples = 0;
    unsigned valid_samples = 0;
    unsigned current_invalid_samples = 0;
    unsigned longest_invalid_samples = 0;
};

} // namespace

int main(int argc, char **argv)
{
    double duration_seconds = 15.0;
    if (argc > 2) {
        std::fprintf(stderr, "usage: %s [seconds; 0 means until Ctrl-C]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        char *end = nullptr;
        duration_seconds = std::strtod(argv[1], &end);
        if (end == argv[1] || *end != '\0' || duration_seconds < 0.0) {
            std::fprintf(stderr, "invalid duration: %s\n", argv[1]);
            return 2;
        }
    }

    vr::EVRInitError init_error = vr::VRInitError_None;
    vr::IVRSystem *system = vr::VR_Init(&init_error, vr::VRApplication_Background);
    if (init_error != vr::VRInitError_None || system == nullptr) {
        std::fprintf(stderr, "OpenVR initialization failed: %s\n",
                     vr::VR_GetVRInitErrorAsEnglishDescription(init_error));
        return 1;
    }

    DeviceStats stats[vr::k_unMaxTrackedDeviceCount]{};
    vr::TrackedDevicePose_t poses[vr::k_unMaxTrackedDeviceCount]{};
    const auto start = std::chrono::steady_clock::now();
    auto next_report = start;
    unsigned sample_count = 0;

    std::puts("Live OpenVR poses (Space Calibrator requires 'TRACKED (running/OK)').");
    std::puts("Keep the HMD awake and expose the controller sensor ring to a base station.");

    while (true) {
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - start).count();
        if (duration_seconds > 0.0 && elapsed >= duration_seconds) {
            break;
        }

        system->GetDeviceToAbsoluteTrackingPose(
            vr::TrackingUniverseStanding, 0.0f, poses, vr::k_unMaxTrackedDeviceCount);
        ++sample_count;

        for (vr::TrackedDeviceIndex_t id = 0; id < vr::k_unMaxTrackedDeviceCount; ++id) {
            const auto device_class = system->GetTrackedDeviceClass(id);
            const bool relevant = device_class == vr::TrackedDeviceClass_HMD ||
                                  device_class == vr::TrackedDeviceClass_Controller ||
                                  device_class == vr::TrackedDeviceClass_GenericTracker;
            if (!relevant) {
                continue;
            }

            auto &device = stats[id];
            if (!device.seen) {
                device.seen = true;
                device.relevant = true;
                device.device_class = device_class;
                device.serial = string_property(system, id, vr::Prop_SerialNumber_String);
            }

            const bool tracked = poses[id].bDeviceIsConnected && poses[id].bPoseIsValid &&
                                 poses[id].eTrackingResult == vr::TrackingResult_Running_OK;
            ++device.samples;
            if (tracked) {
                ++device.valid_samples;
                device.current_invalid_samples = 0;
            } else {
                ++device.current_invalid_samples;
                device.longest_invalid_samples =
                    std::max(device.longest_invalid_samples, device.current_invalid_samples);
            }
        }

        if (now >= next_report) {
            std::printf("[%5.1fs]", elapsed);
            for (vr::TrackedDeviceIndex_t id = 0; id < vr::k_unMaxTrackedDeviceCount; ++id) {
                if (!stats[id].relevant) {
                    continue;
                }
                const bool tracked = poses[id].bDeviceIsConnected && poses[id].bPoseIsValid &&
                                     poses[id].eTrackingResult == vr::TrackingResult_Running_OK;
                std::printf("  #%u %s %s: %s (%s)", id, class_name(stats[id].device_class),
                            stats[id].serial.c_str(), tracked ? "TRACKED" : "LOST",
                            tracking_result_name(poses[id].eTrackingResult));
                const auto &matrix = poses[id].mDeviceToAbsoluteTracking;
                std::printf(" pos=(%.2f,%.2f,%.2f)m", matrix.m[0][3], matrix.m[1][3],
                            matrix.m[2][3]);
                if (stats[id].device_class == vr::TrackedDeviceClass_HMD) {
                    const auto &angular = poses[id].vAngularVelocity;
                    const double angular_speed =
                        std::sqrt(angular.v[0] * angular.v[0] + angular.v[1] * angular.v[1] +
                                  angular.v[2] * angular.v[2]) *
                        (180.0 / 3.14159265358979323846);
                    std::printf(" upY=%.3f ang=%.1fdps", matrix.m[1][1], angular_speed);
                }
            }
            std::putchar('\n');
            std::fflush(stdout);
            next_report = now + std::chrono::seconds(1);
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    std::puts("\nTracking summary:");
    for (vr::TrackedDeviceIndex_t id = 0; id < vr::k_unMaxTrackedDeviceCount; ++id) {
        const auto &device = stats[id];
        if (!device.relevant || device.samples == 0) {
            continue;
        }
        const double valid_percent = 100.0 * device.valid_samples / device.samples;
        const double longest_dropout = 0.02 * device.longest_invalid_samples;
        std::printf("  #%u %-10s %-24s %6.1f%% tracked; longest dropout %.2fs\n", id,
                    class_name(device.device_class), device.serial.c_str(), valid_percent,
                    longest_dropout);
    }

    vr::VR_Shutdown();
    return sample_count == 0 ? 1 : 0;
}
