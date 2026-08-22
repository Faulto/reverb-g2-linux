#include <openvr.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;

struct Quaternion {
    double w;
    double x;
    double y;
    double z;
};

struct Sample {
    std::array<double, 3> position;
    Quaternion orientation;
    double angular_speed_dps;
    double linear_speed_mps;
};

Quaternion matrix_to_quaternion(const vr::HmdMatrix34_t &m)
{
    Quaternion q{};
    const double trace = m.m[0][0] + m.m[1][1] + m.m[2][2];
    if (trace > 0.0) {
        const double s = std::sqrt(trace + 1.0) * 2.0;
        q.w = 0.25 * s;
        q.x = (m.m[2][1] - m.m[1][2]) / s;
        q.y = (m.m[0][2] - m.m[2][0]) / s;
        q.z = (m.m[1][0] - m.m[0][1]) / s;
    } else if (m.m[0][0] > m.m[1][1] && m.m[0][0] > m.m[2][2]) {
        const double s = std::sqrt(1.0 + m.m[0][0] - m.m[1][1] - m.m[2][2]) * 2.0;
        q.w = (m.m[2][1] - m.m[1][2]) / s;
        q.x = 0.25 * s;
        q.y = (m.m[0][1] + m.m[1][0]) / s;
        q.z = (m.m[0][2] + m.m[2][0]) / s;
    } else if (m.m[1][1] > m.m[2][2]) {
        const double s = std::sqrt(1.0 + m.m[1][1] - m.m[0][0] - m.m[2][2]) * 2.0;
        q.w = (m.m[0][2] - m.m[2][0]) / s;
        q.x = (m.m[0][1] + m.m[1][0]) / s;
        q.y = 0.25 * s;
        q.z = (m.m[1][2] + m.m[2][1]) / s;
    } else {
        const double s = std::sqrt(1.0 + m.m[2][2] - m.m[0][0] - m.m[1][1]) * 2.0;
        q.w = (m.m[1][0] - m.m[0][1]) / s;
        q.x = (m.m[0][2] + m.m[2][0]) / s;
        q.y = (m.m[1][2] + m.m[2][1]) / s;
        q.z = 0.25 * s;
    }
    const double length = std::sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
    return {q.w / length, q.x / length, q.y / length, q.z / length};
}

double quaternion_dot(const Quaternion &a, const Quaternion &b)
{
    return a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
}

double percentile(std::vector<double> values, double fraction)
{
    if (values.empty()) {
        return 0.0;
    }
    std::sort(values.begin(), values.end());
    const double index = fraction * static_cast<double>(values.size() - 1);
    const auto lower = static_cast<std::size_t>(std::floor(index));
    const auto upper = static_cast<std::size_t>(std::ceil(index));
    const double mix = index - static_cast<double>(lower);
    return values[lower] * (1.0 - mix) + values[upper] * mix;
}

double vector_length(const vr::HmdVector3_t &v)
{
    return std::sqrt(static_cast<double>(v.v[0]) * v.v[0] +
                     static_cast<double>(v.v[1]) * v.v[1] +
                     static_cast<double>(v.v[2]) * v.v[2]);
}

} // namespace

int main(int argc, char **argv)
{
    double duration_seconds = 10.0;
    if (argc > 2) {
        std::fprintf(stderr, "usage: %s [seconds]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        char *end = nullptr;
        duration_seconds = std::strtod(argv[1], &end);
        if (end == argv[1] || *end != '\0' || !std::isfinite(duration_seconds) ||
            duration_seconds < 2.0 || duration_seconds > 120.0) {
            std::fprintf(stderr, "duration must be between 2 and 120 seconds: %s\n", argv[1]);
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

    std::puts("Stationary HMD pose capture.");
    std::puts("For a tracker-only baseline, put the HMD on a rigid surface with its cameras seeing a lit, textured room.");
    std::puts("Warming up for 1 second, then capturing...");
    std::this_thread::sleep_for(std::chrono::seconds(1));

    std::vector<Sample> samples;
    unsigned polls = 0;
    const auto start = std::chrono::steady_clock::now();
    while (std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count() <
           duration_seconds) {
        vr::TrackedDevicePose_t poses[vr::k_unMaxTrackedDeviceCount]{};
        system->GetDeviceToAbsoluteTrackingPose(
            vr::TrackingUniverseStanding, 0.0f, poses, vr::k_unMaxTrackedDeviceCount);
        ++polls;
        const auto &hmd = poses[vr::k_unTrackedDeviceIndex_Hmd];
        if (hmd.bDeviceIsConnected && hmd.bPoseIsValid &&
            hmd.eTrackingResult == vr::TrackingResult_Running_OK) {
            const auto &m = hmd.mDeviceToAbsoluteTracking;
            samples.push_back({
                {m.m[0][3], m.m[1][3], m.m[2][3]},
                matrix_to_quaternion(m),
                vector_length(hmd.vAngularVelocity) * 180.0 / kPi,
                vector_length(hmd.vVelocity),
            });
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    if (samples.size() < 20) {
        std::fprintf(stderr, "Only %zu/%u HMD samples were valid; tracking was not stable enough to measure.\n",
                     samples.size(), polls);
        vr::VR_Shutdown();
        return 1;
    }

    std::array<double, 3> mean_position{};
    Quaternion mean_orientation{};
    const Quaternion reference = samples.front().orientation;
    for (const auto &sample : samples) {
        for (std::size_t axis = 0; axis < 3; ++axis) {
            mean_position[axis] += sample.position[axis];
        }
        Quaternion q = sample.orientation;
        if (quaternion_dot(q, reference) < 0.0) {
            q = {-q.w, -q.x, -q.y, -q.z};
        }
        mean_orientation.w += q.w;
        mean_orientation.x += q.x;
        mean_orientation.y += q.y;
        mean_orientation.z += q.z;
    }
    for (double &component : mean_position) {
        component /= static_cast<double>(samples.size());
    }
    const double qlength = std::sqrt(mean_orientation.w * mean_orientation.w +
                                     mean_orientation.x * mean_orientation.x +
                                     mean_orientation.y * mean_orientation.y +
                                     mean_orientation.z * mean_orientation.z);
    mean_orientation = {mean_orientation.w / qlength, mean_orientation.x / qlength,
                        mean_orientation.y / qlength, mean_orientation.z / qlength};

    std::array<double, 3> minimum = samples.front().position;
    std::array<double, 3> maximum = samples.front().position;
    std::array<double, 3> squared_axis_error{};
    std::vector<double> position_errors_mm;
    std::vector<double> angular_errors_deg;
    std::vector<double> angular_speeds_dps;
    std::vector<double> linear_speeds_mps;
    position_errors_mm.reserve(samples.size());
    angular_errors_deg.reserve(samples.size());
    angular_speeds_dps.reserve(samples.size());
    linear_speeds_mps.reserve(samples.size());

    for (const auto &sample : samples) {
        double squared_position_error = 0.0;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            minimum[axis] = std::min(minimum[axis], sample.position[axis]);
            maximum[axis] = std::max(maximum[axis], sample.position[axis]);
            const double error = sample.position[axis] - mean_position[axis];
            squared_axis_error[axis] += error * error;
            squared_position_error += error * error;
        }
        position_errors_mm.push_back(std::sqrt(squared_position_error) * 1000.0);
        const double dot = std::clamp(std::abs(quaternion_dot(sample.orientation, mean_orientation)),
                                      0.0, 1.0);
        angular_errors_deg.push_back(2.0 * std::acos(dot) * 180.0 / kPi);
        angular_speeds_dps.push_back(sample.angular_speed_dps);
        linear_speeds_mps.push_back(sample.linear_speed_mps);
    }

    const auto centroid = [&samples](std::size_t begin, std::size_t end) {
        std::array<double, 3> result{};
        for (std::size_t index = begin; index < end; ++index) {
            for (std::size_t axis = 0; axis < 3; ++axis) {
                result[axis] += samples[index].position[axis];
            }
        }
        const double count = static_cast<double>(end - begin);
        for (double &component : result) {
            component /= count;
        }
        return result;
    };
    const std::size_t quarter = std::max<std::size_t>(1, samples.size() / 4);
    const auto first_centroid = centroid(0, quarter);
    const auto last_centroid = centroid(samples.size() - quarter, samples.size());
    double drift_squared = 0.0;
    for (std::size_t axis = 0; axis < 3; ++axis) {
        const double delta = last_centroid[axis] - first_centroid[axis];
        drift_squared += delta * delta;
    }

    const auto rms = [](const std::vector<double> &values) {
        double sum = 0.0;
        for (double value : values) {
            sum += value * value;
        }
        return std::sqrt(sum / static_cast<double>(values.size()));
    };

    std::printf("\nValid pose samples: %zu/%u (%.1f%%, %.1f samples/s)\n", samples.size(), polls,
                100.0 * samples.size() / std::max(1u, polls), samples.size() / duration_seconds);
    std::printf("Mean standing position: (%.4f, %.4f, %.4f)m\n", mean_position[0],
                mean_position[1], mean_position[2]);
    std::printf("Position about mean: RMS %.2fmm, p95 %.2fmm, max %.2fmm\n",
                rms(position_errors_mm), percentile(position_errors_mm, 0.95),
                *std::max_element(position_errors_mm.begin(), position_errors_mm.end()));
    std::printf("Position peak-to-peak: X %.2fmm, Y %.2fmm, Z %.2fmm; first-to-last drift %.2fmm\n",
                (maximum[0] - minimum[0]) * 1000.0, (maximum[1] - minimum[1]) * 1000.0,
                (maximum[2] - minimum[2]) * 1000.0, std::sqrt(drift_squared) * 1000.0);
    std::printf("Orientation about mean: RMS %.4fdeg, p95 %.4fdeg, max %.4fdeg\n",
                rms(angular_errors_deg), percentile(angular_errors_deg, 0.95),
                *std::max_element(angular_errors_deg.begin(), angular_errors_deg.end()));
    std::printf("Reported velocity p95: angular %.2fdeg/s, linear %.3fm/s\n",
                percentile(angular_speeds_dps, 0.95), percentile(linear_speeds_mps, 0.95));
    std::puts("These figures include any real motion; use the rigid-surface capture to isolate tracker noise.");

    vr::VR_Shutdown();
    return 0;
}
