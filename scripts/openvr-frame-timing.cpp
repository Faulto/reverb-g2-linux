#include <openvr.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

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
        if (end == argv[1] || *end != '\0' || duration_seconds <= 0.0) {
            std::fprintf(stderr, "invalid duration: %s\n", argv[1]);
            return 2;
        }
    }

    vr::EVRInitError init_error = vr::VRInitError_None;
    vr::IVRSystem *system = vr::VR_Init(&init_error, vr::VRApplication_Background);
    if (init_error != vr::VRInitError_None || system == nullptr || vr::VRCompositor() == nullptr) {
        std::fprintf(stderr, "OpenVR initialization failed: %s\n",
                     vr::VR_GetVRInitErrorAsEnglishDescription(init_error));
        return 1;
    }

    vr::Compositor_CumulativeStats first{};
    vr::Compositor_CumulativeStats last{};
    vr::VRCompositor()->GetCumulativeStats(&first, sizeof(first));

    const auto start = std::chrono::steady_clock::now();
    auto next_report = start;
    std::puts("Live SteamVR compositor timing:");

    while (true) {
        const auto now = std::chrono::steady_clock::now();
        const double elapsed = std::chrono::duration<double>(now - start).count();
        if (elapsed >= duration_seconds) {
            break;
        }

        if (now >= next_report) {
            vr::Compositor_FrameTiming timing{};
            timing.m_nSize = sizeof(timing);
            if (vr::VRCompositor()->GetFrameTiming(&timing, 0)) {
                const unsigned predicted = VR_COMPOSITOR_ADDITIONAL_PREDICTED_FRAMES(timing);
                const unsigned throttled = VR_COMPOSITOR_NUMBER_OF_THROTTLED_FRAMES(timing);
                const bool motion_smoothing =
                    (timing.m_nReprojectionFlags & vr::VRCompositor_ReprojectionMotion) != 0;
                std::printf(
                    "[%4.1fs] frame=%u interval=%5.2fms appGPU=%5.2fms compGPU=%4.2fms "
                    "presents=%u dropped=%u motion=%s predicted=%u throttled=%u\n",
                    elapsed, timing.m_nFrameIndex, timing.m_flClientFrameIntervalMs,
                    timing.m_flPreSubmitGpuMs + timing.m_flPostSubmitGpuMs,
                    timing.m_flCompositorRenderGpuMs, timing.m_nNumFramePresents,
                    timing.m_nNumDroppedFrames, motion_smoothing ? "yes" : "no", predicted,
                    throttled);
                std::fflush(stdout);
            } else {
                std::puts("No compositor frame timing is available.");
            }
            next_report = now + std::chrono::seconds(1);
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    vr::VRCompositor()->GetCumulativeStats(&last, sizeof(last));
    const auto delta = [](uint32_t end, uint32_t begin) { return end >= begin ? end - begin : 0; };
    const uint32_t presents = delta(last.m_nNumFramePresents, first.m_nNumFramePresents);
    const uint32_t dropped = delta(last.m_nNumDroppedFrames, first.m_nNumDroppedFrames);
    const uint32_t reprojected =
        delta(last.m_nNumReprojectedFrames, first.m_nNumReprojectedFrames);

    std::printf("\n%.1f-second summary for scene PID %u:\n", duration_seconds, last.m_nPid);
    std::printf("  presents:    %u (%.1f/s)\n", presents, presents / duration_seconds);
    std::printf("  dropped:     %u\n", dropped);
    std::printf("  reprojected: %u\n", reprojected);

    vr::VR_Shutdown();
    return 0;
}
