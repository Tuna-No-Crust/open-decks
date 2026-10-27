#pragma once

#include <array>

#include "controllers/controller.h"
#include "controllers/hid/legacyhidcontrollermapping.h"

struct SDL_Gamepad;

/// A game controller read through SDL's gamepad API.
///
/// SDL normalises every supported pad (Xbox, PlayStation, Switch, Steam Deck,
/// generic HID) to one standard layout, so a single mapping works for all of
/// them. The state is polled on the ControllerManager's poll timer and handed
/// to the mapping script as a fixed-layout report whenever it changes:
///
///   offset  size  content
///   0       1     report version (kReportVersion)
///   1       12    6 x int16 axes in SDL_GamepadAxis order: left x/y,
///                 right x/y (-32768..32767, y down-positive), left/right
///                 trigger (0..32767)
///   13      4     uint32 button bitmask, bit n = SDL_GamepadButton n
///   17      4     uint32 microseconds since the previous report
///   21      1     number of touchpads on the pad (0..kMaxTouchpads)
///   22      28    kMaxTouchpads x kMaxFingers finger slots of 7 bytes each,
///                 touchpad-major: uint8 down, uint16 x, uint16 y (0..65535
///                 across the pad, y down-positive), uint16 pressure
///
/// All values little-endian. Fingers on a touchpad the pad doesn't have, or
/// beyond the fingers it tracks, read as up at 0/0. The Steam Deck reports
/// its two trackpads as two one-finger touchpads, a DualSense its one
/// touchpad with two fingers. If the pad disconnects, one all-at-rest report
/// is sent and the controller keeps looking for the same model to come back
/// (a replug gets a new SDL ID). Mappings use the HID mapping format with the
/// .gamepad.xml extension; output (rumble, lightbar) is not supported yet.
class SdlGamepadController : public Controller {
    Q_OBJECT
  public:
    static constexpr quint8 kReportVersion = 2;
    static constexpr int kMaxTouchpads = 2;
    static constexpr int kMaxFingers = 2;
    static constexpr int kFingerSize = 7;
    static constexpr int kReportSize = 22 + kMaxTouchpads * kMaxFingers * kFingerSize;

    SdlGamepadController(quint32 joystickId,
            const QString& name,
            quint16 vendorId,
            quint16 productId);
    ~SdlGamepadController() override;

    QString mappingExtension() override;
    QString defaultMappingFile() const override;

    void setMapping(std::shared_ptr<LegacyControllerMapping> pMapping) override;

    QList<LegacyControllerMapping::ScriptFileInfo> getMappingScriptFiles() override;
    QList<std::shared_ptr<AbstractLegacyControllerSetting>> getMappingSettings() override;
#ifdef MIXXX_USE_QML
    QList<LegacyControllerMapping::QMLModuleInfo> getMappingModules() override;
    QList<LegacyControllerMapping::ScreenInfo> getMappingInfoScreens() override;
#endif

    PhysicalTransportProtocol getPhysicalTransportProtocol() const override {
        return m_transport;
    }
    DataRepresentationProtocol getDataRepresentationProtocol() const override {
        return DataRepresentationProtocol::GAMEPAD;
    }

    QString getVendorString() const override {
        return QString();
    }
    QString getProductString() const override {
        return getName();
    }
    std::optional<uint16_t> getVendorId() const override {
        return m_vendorId;
    }
    std::optional<uint16_t> getProductId() const override {
        return m_productId;
    }
    QString getSerialNumber() const override {
        return m_serial;
    }
    std::optional<uint8_t> getUsbInterfaceNumber() const override {
        return std::nullopt;
    }

    bool isMappable() const override {
        // Report-based like HID; there are no discrete messages to learn.
        return false;
    }

    bool matchMapping(const MappingInfo& mapping) override;

  private:
    int open(const QString& resourcePath) override;
    int close() override;
    bool poll() override;
    bool isPolling() const override {
        return isOpen();
    }

    bool sendBytes(const QByteArray& data) override;

    struct Finger {
        bool down = false;
        quint16 x = 0;
        quint16 y = 0;
        quint16 pressure = 0;
        bool operator==(const Finger&) const = default;
    };

    struct State {
        std::array<qint16, 6> axes{};
        quint32 buttons = 0;
        quint8 touchpads = 0;
        std::array<Finger, kMaxTouchpads * kMaxFingers> fingers{};
        bool operator==(const State&) const = default;
    };

    /// Reports the state to the mapping if it differs from the last one.
    bool sendState(const State& state);
    /// After a disconnect: pick the same model back up under its new ID.
    bool reattach();

    quint32 m_joystickId;
    const quint16 m_vendorId;
    const quint16 m_productId;
    QString m_serial;
    PhysicalTransportProtocol m_transport;

    SDL_Gamepad* m_pGamepad;
    bool m_disconnected;
    State m_lastState;
    mixxx::Duration m_lastReportTime;
    mixxx::Duration m_lastReattachAttempt;

    std::unique_ptr<LegacyHidControllerMapping> m_pMapping;
};
