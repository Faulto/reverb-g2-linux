#include <openvr.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <thread>

namespace {

constexpr double kPi = 3.14159265358979323846;

struct Quaternion {
    double w = 1.0;
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

const char *calibration_name(vr::ChaperoneCalibrationState state)
{
    switch (state) {
    case vr::ChaperoneCalibrationState_OK:
        return "OK";
    case vr::ChaperoneCalibrationState_Warning:
        return "warning";
    case vr::ChaperoneCalibrationState_Warning_BaseStationMayHaveMoved:
        return "warning: base station may have moved";
    case vr::ChaperoneCalibrationState_Warning_BaseStationRemoved:
        return "warning: base station removed";
    case vr::ChaperoneCalibrationState_Warning_SeatedBoundsInvalid:
        return "warning: seated bounds invalid";
    case vr::ChaperoneCalibrationState_Error:
        return "error";
    case vr::ChaperoneCalibrationState_Error_BaseStationUninitialized:
        return "error: base station uninitialized";
    case vr::ChaperoneCalibrationState_Error_BaseStationConflict:
        return "error: base station conflict";
    case vr::ChaperoneCalibrationState_Error_PlayAreaInvalid:
        return "error: play area invalid";
    case vr::ChaperoneCalibrationState_Error_CollisionBoundsInvalid:
        return "error: collision bounds invalid";
    default:
        return "unknown";
    }
}

Quaternion matrix_to_quaternion(const vr::HmdMatrix34_t &m)
{
    Quaternion q;
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
    return q;
}

vr::HmdMatrix34_t quaternion_matrix(const Quaternion &q)
{
    const double xx = q.x * q.x;
    const double yy = q.y * q.y;
    const double zz = q.z * q.z;
    const double xy = q.x * q.y;
    const double xz = q.x * q.z;
    const double yz = q.y * q.z;
    const double wx = q.w * q.x;
    const double wy = q.w * q.y;
    const double wz = q.w * q.z;

    vr::HmdMatrix34_t m{};
    m.m[0][0] = static_cast<float>(1.0 - 2.0 * (yy + zz));
    m.m[0][1] = static_cast<float>(2.0 * (xy - wz));
    m.m[0][2] = static_cast<float>(2.0 * (xz + wy));
    m.m[1][0] = static_cast<float>(2.0 * (xy + wz));
    m.m[1][1] = static_cast<float>(1.0 - 2.0 * (xx + zz));
    m.m[1][2] = static_cast<float>(2.0 * (yz - wx));
    m.m[2][0] = static_cast<float>(2.0 * (xz - wy));
    m.m[2][1] = static_cast<float>(2.0 * (yz + wx));
    m.m[2][2] = static_cast<float>(1.0 - 2.0 * (xx + yy));
    return m;
}

double position_distance(const vr::HmdMatrix34_t &a, const vr::HmdMatrix34_t &b)
{
    const double dx = a.m[0][3] - b.m[0][3];
    const double dy = a.m[1][3] - b.m[1][3];
    const double dz = a.m[2][3] - b.m[2][3];
    return std::sqrt(dx * dx + dy * dy + dz * dz);
}

bool get_hmd_pose(vr::IVRSystem *system, vr::ETrackingUniverseOrigin origin, vr::HmdMatrix34_t *matrix)
{
    vr::TrackedDevicePose_t poses[vr::k_unMaxTrackedDeviceCount]{};
    system->GetDeviceToAbsoluteTrackingPose(origin, 0.0f, poses, vr::k_unMaxTrackedDeviceCount);
    const auto &hmd = poses[vr::k_unTrackedDeviceIndex_Hmd];
    if (!hmd.bDeviceIsConnected || !hmd.bPoseIsValid ||
        hmd.eTrackingResult != vr::TrackingResult_Running_OK) {
        return false;
    }
    *matrix = hmd.mDeviceToAbsoluteTracking;
    return true;
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

void print_pose(const char *label, const vr::HmdMatrix34_t &m)
{
    const Quaternion q = matrix_to_quaternion(m);
    const double yaw = std::atan2(m.m[0][2], m.m[2][2]) * 180.0 / kPi;
    std::printf("%s pos=(%.3f, %.3f, %.3f)m yaw=%.1fdeg quat=(%.4f, %.4f, %.4f, %.4f)\n",
                label, m.m[0][3], m.m[1][3], m.m[2][3], yaw, q.w, q.x, q.y, q.z);
}

void print_status(vr::IVRSystem *system)
{
    vr::HmdMatrix34_t raw{};
    vr::HmdMatrix34_t standing{};
    const bool raw_ok = get_hmd_pose(system, vr::TrackingUniverseRawAndUncalibrated, &raw);
    const bool standing_ok = get_hmd_pose(system, vr::TrackingUniverseStanding, &standing);

    auto *chaperone = vr::VRChaperone();
    auto *setup = vr::VRChaperoneSetup();
    const auto state = chaperone->GetCalibrationState();
    std::printf("Chaperone calibration: %s (%d)\n", calibration_name(state), state);
    if (raw_ok) {
        print_pose("HMD raw:     ", raw);
    } else {
        std::puts("HMD raw:      not tracked");
    }
    if (standing_ok) {
        print_pose("HMD standing:", standing);
    } else {
        std::puts("HMD standing: not tracked");
    }

    setup->RevertWorkingCopy();
    vr::HmdMatrix34_t origin{};
    float width = 0.0f;
    float depth = 0.0f;
    if (setup->GetWorkingStandingZeroPoseToRawTrackingPose(&origin)) {
        print_pose("Standing->raw:", origin);
    } else {
        std::puts("Standing->raw: missing");
    }
    if (setup->GetWorkingPlayAreaSize(&width, &depth)) {
        std::printf("Play area: %.2f x %.2f m\n", width, depth);
    } else {
        std::puts("Play area: missing");
    }
}

int check_ready(vr::IVRSystem *system, double expected_eye_height)
{
    constexpr int wanted_samples = 100;
    constexpr auto sample_interval = std::chrono::milliseconds(20);
    int valid_samples = 0;
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
    double up_y = 0.0;
    vr::HmdMatrix34_t first{};
    vr::HmdMatrix34_t last{};

    std::puts("Checking the live standing space for 2 seconds...");
    for (int index = 0; index < wanted_samples; ++index) {
        vr::HmdMatrix34_t sample{};
        if (get_hmd_pose(system, vr::TrackingUniverseStanding, &sample)) {
            if (valid_samples == 0) {
                first = sample;
            }
            last = sample;
            x += sample.m[0][3];
            y += sample.m[1][3];
            z += sample.m[2][3];
            up_y += sample.m[1][1];
            ++valid_samples;
        }
        std::this_thread::sleep_for(sample_interval);
    }

    bool ready = true;
    const auto state = vr::VRChaperone()->GetCalibrationState();
    std::printf("Chaperone calibration: %s (%d)\n", calibration_name(state), state);
    if (state != vr::ChaperoneCalibrationState_OK) {
        ready = false;
    }
    if (valid_samples < wanted_samples * 9 / 10) {
        std::fprintf(stderr, "HMD tracking was valid for only %d/%d samples.\n", valid_samples,
                     wanted_samples);
        ready = false;
    }
    if (valid_samples > 0) {
        x /= valid_samples;
        y /= valid_samples;
        z /= valid_samples;
        up_y /= valid_samples;
        const double displacement = position_distance(first, last);
        std::printf("HMD standing mean: pos=(%.3f, %.3f, %.3f)m upY=%.3f; 2s displacement %.1fmm\n",
                    x, y, z, up_y, displacement * 1000.0);
        const double height_error = std::abs(y - expected_eye_height);
        const double centre_error = std::sqrt(x * x + z * z);
        if (height_error > 0.25) {
            std::fprintf(stderr,
                         "HMD height is %.2fm from the expected %.2fm. Stand upright at centre; if it remains wrong, run origin set %.2f.\n",
                         y, expected_eye_height, expected_eye_height);
            ready = false;
        }
        if (centre_error > 0.75) {
            std::fprintf(stderr,
                         "HMD is %.2fm horizontally from play centre. Stand at centre for this check.\n",
                         centre_error);
            ready = false;
        }
        if (up_y < 0.75) {
            std::fprintf(stderr, "HMD is not reasonably upright (upY %.3f).\n", up_y);
            ready = false;
        }
        if (displacement > 0.20) {
            std::fprintf(stderr,
                         "HMD moved %.2fm during the check; keep still or investigate SLAM drift.\n",
                         displacement);
            ready = false;
        }
    }

    vr::TrackedDevicePose_t poses[vr::k_unMaxTrackedDeviceCount]{};
    system->GetDeviceToAbsoluteTrackingPose(
        vr::TrackingUniverseStanding, 0.0f, poses, vr::k_unMaxTrackedDeviceCount);
    int tracked_controllers = 0;
    for (vr::TrackedDeviceIndex_t id = 0; id < vr::k_unMaxTrackedDeviceCount; ++id) {
        if (system->GetTrackedDeviceClass(id) != vr::TrackedDeviceClass_Controller) {
            continue;
        }
        const auto &pose = poses[id];
        const std::string serial = string_property(system, id, vr::Prop_SerialNumber_String);
        if (!pose.bDeviceIsConnected || !pose.bPoseIsValid ||
            pose.eTrackingResult != vr::TrackingResult_Running_OK) {
            std::printf("Controller %s: not tracked\n", serial.c_str());
            continue;
        }
        ++tracked_controllers;
        const auto &m = pose.mDeviceToAbsoluteTracking;
        const double dx = m.m[0][3] - x;
        const double dy = m.m[1][3] - y;
        const double dz = m.m[2][3] - z;
        const double hmd_distance = std::sqrt(dx * dx + dy * dy + dz * dz);
        std::printf("Controller %s: tracked at (%.2f, %.2f, %.2f)m, %.2fm from HMD\n",
                    serial.c_str(), m.m[0][3], m.m[1][3], m.m[2][3], hmd_distance);
        if (hmd_distance > 3.0) {
            std::fprintf(stderr,
                         "Controller %s is implausibly far from the HMD; the Space Calibrator transform is stale.\n",
                         serial.c_str());
            ready = false;
        }
    }
    if (tracked_controllers < 2) {
        std::fprintf(stderr, "Only %d/2 controllers are tracked.\n", tracked_controllers);
        ready = false;
    }

    std::puts(ready ? "READY: floor, headset, and both controller spaces pass the live checks."
                    : "NOT READY: correct the failures above before starting Beat Saber.");
    return ready ? 0 : 1;
}

bool parse_number(const char *text, double low, double high, double *value)
{
    char *end = nullptr;
    const double parsed = std::strtod(text, &end);
    if (end == text || *end != '\0' || !std::isfinite(parsed) || parsed < low || parsed > high) {
        return false;
    }
    *value = parsed;
    return true;
}

void set_corner(vr::HmdVector3_t *corner, float x, float y, float z)
{
    corner->v[0] = x;
    corner->v[1] = y;
    corner->v[2] = z;
}

void make_collision_bounds(float width, float depth, vr::HmdQuad_t (&bounds)[4])
{
    const float x = width * 0.5f;
    const float z = depth * 0.5f;
    constexpr float h = 2.5f;

    set_corner(&bounds[0].vCorners[0], -x, 0, -z);
    set_corner(&bounds[0].vCorners[1], -x, h, -z);
    set_corner(&bounds[0].vCorners[2], x, h, -z);
    set_corner(&bounds[0].vCorners[3], x, 0, -z);

    set_corner(&bounds[1].vCorners[0], x, 0, -z);
    set_corner(&bounds[1].vCorners[1], x, h, -z);
    set_corner(&bounds[1].vCorners[2], x, h, z);
    set_corner(&bounds[1].vCorners[3], x, 0, z);

    set_corner(&bounds[2].vCorners[0], x, 0, z);
    set_corner(&bounds[2].vCorners[1], x, h, z);
    set_corner(&bounds[2].vCorners[2], -x, h, z);
    set_corner(&bounds[2].vCorners[3], -x, 0, z);

    set_corner(&bounds[3].vCorners[0], -x, 0, z);
    set_corner(&bounds[3].vCorners[1], -x, h, z);
    set_corner(&bounds[3].vCorners[2], -x, h, -z);
    set_corner(&bounds[3].vCorners[3], -x, 0, -z);
}

bool commit_origin(const vr::HmdMatrix34_t &standing_to_raw, double width, double depth)
{
    vr::HmdQuad_t bounds[4]{};
    make_collision_bounds(static_cast<float>(width), static_cast<float>(depth), bounds);

    auto *setup = vr::VRChaperoneSetup();
    setup->RoomSetupStarting();
    setup->RevertWorkingCopy();
    setup->SetWorkingPlayAreaSize(static_cast<float>(width), static_cast<float>(depth));
    setup->SetWorkingCollisionBoundsInfo(bounds, 4);
    setup->SetWorkingStandingZeroPoseToRawTrackingPose(&standing_to_raw);
    setup->SetWorkingSeatedZeroPoseToRawTrackingPose(&standing_to_raw);
    if (!setup->CommitWorkingCopy(vr::EChaperoneConfigFile_Live)) {
        std::fputs("SteamVR rejected CommitWorkingCopy; no origin was saved.\n", stderr);
        return false;
    }
    setup->ReloadFromDisk(vr::EChaperoneConfigFile_Live);
    std::this_thread::sleep_for(std::chrono::milliseconds(750));
    return true;
}

int adopt_identity_origin(vr::IVRSystem *system, double width, double depth)
{
    vr::HmdMatrix34_t first{};
    vr::HmdMatrix34_t last{};
    if (!get_hmd_pose(system, vr::TrackingUniverseRawAndUncalibrated, &first)) {
        std::fputs("Refusing to save: the G2 raw pose is not tracked.\n", stderr);
        return 1;
    }
    std::this_thread::sleep_for(std::chrono::seconds(2));
    if (!get_hmd_pose(system, vr::TrackingUniverseRawAndUncalibrated, &last)) {
        std::fputs("Refusing to save: the G2 raw pose was lost during validation.\n", stderr);
        return 1;
    }

    const double displacement = position_distance(first, last);
    const double magnitude = std::sqrt(last.m[0][3] * last.m[0][3] + last.m[1][3] * last.m[1][3] +
                                       last.m[2][3] * last.m[2][3]);
    if (displacement > 0.35 || magnitude > 20.0 || last.m[1][1] < 0.8f) {
        std::fprintf(stderr,
                     "Refusing identity origin: displacement=%.2fm, |position|=%.2fm, upY=%.3f.\n"
                     "The raw Monado pose is not a stable, upright room-scale pose.\n",
                     displacement, magnitude, last.m[1][1]);
        print_pose("First raw:", first);
        print_pose("Last raw: ", last);
        return 1;
    }

    vr::HmdMatrix34_t identity{};
    identity.m[0][0] = 1.0f;
    identity.m[1][1] = 1.0f;
    identity.m[2][2] = 1.0f;
    if (!commit_origin(identity, width, depth)) {
        return 1;
    }

    std::puts("Identity standing origin saved (Monado already supplies the nominal 1.6m stage offset). ");
    print_pose("HMD raw:     ", last);
    std::printf("Play area: %.2f x %.2fm\n", width, depth);
    return 0;
}

int set_origin(vr::IVRSystem *system,
               double eye_height,
               double width,
               double depth,
               bool countdown)
{
    if (countdown) {
        std::puts("Stand at the desired centre, wear the HMD, look straight and level, and keep still.");
        for (int seconds = 5; seconds > 0; --seconds) {
            std::printf("Capturing in %d...\n", seconds);
            std::fflush(stdout);
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    } else {
        std::puts("Validating the upright startup pose before setting the floor...");
    }

    constexpr int wanted_samples = 120;
    constexpr auto sample_interval = std::chrono::milliseconds(16);
    vr::HmdMatrix34_t first{};
    vr::HmdMatrix34_t last{};
    vr::HmdMatrix34_t sample{};
    bool have_first = false;
    bool invalid_sample = false;
    int samples = 0;
    double px = 0.0;
    double py = 0.0;
    double pz = 0.0;
    double max_magnitude = 0.0;
    double max_excursion = 0.0;
    double min_up_y = 1.0;
    Quaternion qsum{0.0, 0.0, 0.0, 0.0};
    Quaternion qref{};
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);

    while (samples < wanted_samples && std::chrono::steady_clock::now() < deadline) {
        if (!get_hmd_pose(system, vr::TrackingUniverseRawAndUncalibrated, &sample)) {
            std::this_thread::sleep_for(sample_interval);
            continue;
        }
        bool finite = true;
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 4; ++col) {
                finite = finite && std::isfinite(sample.m[row][col]);
            }
        }
        if (!finite) {
            invalid_sample = true;
            break;
        }
        Quaternion q = matrix_to_quaternion(sample);
        if (!have_first) {
            first = sample;
            qref = q;
            have_first = true;
        }
        const double magnitude = std::sqrt(sample.m[0][3] * sample.m[0][3] +
                                           sample.m[1][3] * sample.m[1][3] +
                                           sample.m[2][3] * sample.m[2][3]);
        max_magnitude = std::max(max_magnitude, magnitude);
        max_excursion = std::max(max_excursion, position_distance(first, sample));
        min_up_y = std::min(min_up_y, static_cast<double>(sample.m[1][1]));
        const double dot = q.w * qref.w + q.x * qref.x + q.y * qref.y + q.z * qref.z;
        if (dot < 0.0) {
            q.w = -q.w;
            q.x = -q.x;
            q.y = -q.y;
            q.z = -q.z;
        }
        px += sample.m[0][3];
        py += sample.m[1][3];
        pz += sample.m[2][3];
        qsum.w += q.w;
        qsum.x += q.x;
        qsum.y += q.y;
        qsum.z += q.z;
        last = sample;
        ++samples;
        std::this_thread::sleep_for(sample_interval);
    }

    if (invalid_sample) {
        std::fputs("Refusing to save: the G2 emitted a non-finite raw pose.\n", stderr);
        return 1;
    }
    if (samples < wanted_samples * 9 / 10) {
        std::fprintf(stderr, "Refusing to save: the G2 was not reliably tracked (%d/%d samples).\n",
                     samples, wanted_samples);
        return 1;
    }

    const double capture_seconds = samples * sample_interval.count() / 1000.0;
    const double displacement = position_distance(first, last);
    const double drift_speed = displacement / std::max(0.001, capture_seconds);
    if (max_magnitude > 10.0 || min_up_y < 0.75 || max_excursion > 0.15 ||
        displacement > 0.15 || drift_speed > 0.10) {
        std::fprintf(stderr,
                     "Refusing to save: raw pose failed the safe floor-capture envelope.\n"
                     "  |position|max=%.2fm, upY(min)=%.3f, excursion(max)=%.2fm, drift=%.2fm in %.2fs (%.2fm/s)\n"
                     "Remain upright and still. If you already were, Basalt is unstable and saving its pose would poison the floor.\n",
                     max_magnitude, min_up_y, max_excursion, displacement, capture_seconds,
                     drift_speed);
        print_pose("First raw:", first);
        print_pose("Last raw: ", last);
        return 1;
    }

    const double inv_samples = 1.0 / samples;
    px *= inv_samples;
    py *= inv_samples;
    pz *= inv_samples;
    const double qlength = std::sqrt(qsum.w * qsum.w + qsum.x * qsum.x + qsum.y * qsum.y +
                                     qsum.z * qsum.z);
    if (!std::isfinite(qlength) || qlength < 0.5) {
        std::fputs("Refusing to save: invalid averaged HMD orientation.\n", stderr);
        return 1;
    }
    Quaternion qavg{qsum.w / qlength, qsum.x / qlength, qsum.y / qlength, qsum.z / qlength};
    const vr::HmdMatrix34_t averaged_hmd = quaternion_matrix(qavg);
    const double yaw = std::atan2(averaged_hmd.m[0][2], averaged_hmd.m[2][2]);
    const double c = std::cos(yaw);
    const double s = std::sin(yaw);
    vr::HmdMatrix34_t standing_to_raw{};
    standing_to_raw.m[0][0] = static_cast<float>(c);
    standing_to_raw.m[0][2] = static_cast<float>(s);
    standing_to_raw.m[1][1] = 1.0f;
    standing_to_raw.m[2][0] = static_cast<float>(-s);
    standing_to_raw.m[2][2] = static_cast<float>(c);

    // Keep the tracker's gravity-derived up direction. Only choose a floor, horizontal centre,
    // and yaw: the captured HMD becomes (0, eye_height, 0) and faces SteamVR's -Z direction.
    standing_to_raw.m[0][3] = static_cast<float>(px);
    standing_to_raw.m[1][3] = static_cast<float>(py - eye_height);
    standing_to_raw.m[2][3] = static_cast<float>(pz);

    if (!commit_origin(standing_to_raw, width, depth)) {
        return 1;
    }
    std::puts("Standing origin saved.");
    print_pose("Standing->raw:", standing_to_raw);
    std::printf("Eye height: %.3fm; play area: %.2f x %.2fm\n", eye_height, width, depth);

    vr::HmdMatrix34_t standing_hmd{};
    if (get_hmd_pose(system, vr::TrackingUniverseStanding, &standing_hmd)) {
        print_pose("HMD standing:", standing_hmd);
        const double error = std::sqrt(standing_hmd.m[0][3] * standing_hmd.m[0][3] +
                                       std::pow(standing_hmd.m[1][3] - eye_height, 2.0) +
                                       standing_hmd.m[2][3] * standing_hmd.m[2][3]);
        if (error > 0.25) {
            std::fprintf(stderr,
                         "Warning: SteamVR's live standing pose is still %.2fm from the requested centre.\n",
                         error);
        }
    }
    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 5) {
        std::fprintf(stderr,
                     "usage:\n  %s status\n  %s check <expected-eye-height-metres>\n"
                     "  %s identity [play-area-width] [play-area-depth]\n"
                     "  %s set <eye-height-metres> [play-area-width] [play-area-depth]\n"
                     "  %s set-now <eye-height-metres> [play-area-width] [play-area-depth]\n",
                     argv[0], argv[0], argv[0], argv[0], argv[0]);
        return 2;
    }

    vr::EVRInitError init_error = vr::VRInitError_None;
    vr::IVRSystem *system = vr::VR_Init(&init_error, vr::VRApplication_Utility);
    if (init_error != vr::VRInitError_None || system == nullptr) {
        std::fprintf(stderr, "OpenVR initialization failed: %s\n",
                     vr::VR_GetVRInitErrorAsEnglishDescription(init_error));
        return 1;
    }

    int result = 0;
    if (std::strcmp(argv[1], "status") == 0 && argc == 2) {
        print_status(system);
    } else if (std::strcmp(argv[1], "check") == 0 && argc == 3) {
        double height = 0.0;
        if (!parse_number(argv[2], 0.5, 2.5, &height)) {
            std::fputs("Invalid expected eye height. Value must be metres.\n", stderr);
            result = 2;
        } else {
            result = check_ready(system, height);
        }
    } else if (std::strcmp(argv[1], "identity") == 0) {
        double width = 5.0;
        double depth = 5.0;
        if ((argc >= 3 && !parse_number(argv[2], 0.5, 10.0, &width)) ||
            (argc >= 4 && !parse_number(argv[3], 0.5, 10.0, &depth)) || argc > 4) {
            std::fputs("Invalid play-area dimension. Values must be metres.\n", stderr);
            result = 2;
        } else {
            result = adopt_identity_origin(system, width, depth);
        }
    } else if ((std::strcmp(argv[1], "set") == 0 || std::strcmp(argv[1], "set-now") == 0) &&
               argc >= 3) {
        double height = 0.0;
        double width = 5.0;
        double depth = 5.0;
        if (!parse_number(argv[2], 0.5, 2.5, &height) ||
            (argc >= 4 && !parse_number(argv[3], 0.5, 10.0, &width)) ||
            (argc >= 5 && !parse_number(argv[4], 0.5, 10.0, &depth))) {
            std::fputs("Invalid height/play-area dimension. Values must be metres.\n", stderr);
            result = 2;
        } else {
            result = set_origin(system, height, width, depth, std::strcmp(argv[1], "set") == 0);
        }
    } else {
        std::fprintf(stderr,
                     "usage:\n  %s status\n  %s check <expected-eye-height-metres>\n"
                     "  %s identity [play-area-width] [play-area-depth]\n"
                     "  %s set <eye-height-metres> [play-area-width] [play-area-depth]\n"
                     "  %s set-now <eye-height-metres> [play-area-width] [play-area-depth]\n",
                     argv[0], argv[0], argv[0], argv[0], argv[0]);
        result = 2;
    }

    vr::VR_Shutdown();
    return result;
}
