#include "controllers/gamepad/sdlgamepadcontroller.h"

#include <SDL3/SDL.h>

#include <QStringList>
#include <QtEndian>
#include <algorithm>
#include <cmath>

#include "controllers/defs_controllers.h"
#include "moc_sdlgamepadcontroller.cpp"
#include "util/time.h"

namespace {

// How often a disconnected pad looks for itself reappearing.
constexpr mixxx::Duration kReattachInterval = mixxx::Duration::fromMillis(500);

// Ships in res/controllers; picked when the user hasn't configured this pad.
const QString kDefaultMapping = QStringLiteral("Gamepad DJ.gamepad.xml");

PhysicalTransportProtocol transportOf(SDL_Gamepad* pGamepad) {
    switch (SDL_GetGamepadConnectionState(pGamepad)) {
    case SDL_JOYSTICK_CONNECTION_WIRED:
        return PhysicalTransportProtocol::USB;
    case SDL_JOYSTICK_CONNECTION_WIRELESS:
        return PhysicalTransportProtocol::BlueTooth;
    default:
        return PhysicalTransportProtocol::UNKNOWN;
    }
}

} // namespace

SdlGamepadController::SdlGamepadController(quint32 joystickId,
        const QString& name,
        quint16 vendorId,
        quint16 productId)
        : Controller(name),
          m_joystickId(joystickId),
          m_vendorId(vendorId),
          m_productId(productId),
          m_transport(PhysicalTransportProtocol::UNKNOWN),
          m_pGamepad(nullptr),
          m_disconnected(false) {
    setInputDevice(true);
    setOutputDevice(false);
}

SdlGamepadController::~SdlGamepadController() {
    if (isOpen()) {
        close();
    }
}

QString SdlGamepadController::mappingExtension() {
    return GAMEPAD_MAPPING_EXTENSION;
}

QString SdlGamepadController::defaultMappingFile() const {
    return kDefaultMapping;
}

void SdlGamepadController::setMapping(std::shared_ptr<LegacyControllerMapping> pMapping) {
    m_pMutableMapping = pMapping;
    m_pMapping = downcastAndClone<LegacyHidControllerMapping>(pMapping.get());
}

QList<LegacyControllerMapping::ScriptFileInfo> SdlGamepadController::getMappingScriptFiles() {
    if (!m_pMapping) {
        return {};
    }
    return m_pMapping->getScriptFiles();
}

QList<std::shared_ptr<AbstractLegacyControllerSetting>>
SdlGamepadController::getMappingSettings() {
    if (!m_pMapping) {
        return {};
    }
    return m_pMapping->getSettings();
}

#ifdef MIXXX_USE_QML
QList<LegacyControllerMapping::QMLModuleInfo> SdlGamepadController::getMappingModules() {
    if (!m_pMapping) {
        return {};
    }
    return m_pMapping->getModules();
}

QList<LegacyControllerMapping::ScreenInfo> SdlGamepadController::getMappingInfoScreens() {
    if (!m_pMapping) {
        return {};
    }
    return m_pMapping->getInfoScreens();
}
#endif

bool SdlGamepadController::matchMapping(const MappingInfo& mapping) {
    // A gamepad mapping with no vendor/product targets every pad: SDL has
    // already normalised them all to the same layout.
    for (const auto& product : mapping.getProducts()) {
        if (product.protocol != QStringLiteral("gamepad")) {
            continue;
        }
        bool ok = false;
        if (!product.vendor_id.isEmpty() &&
                product.vendor_id.toUShort(&ok, 16) != m_vendorId) {
            continue;
        }
        if (!product.product_id.isEmpty() &&
                product.product_id.toUShort(&ok, 16) != m_productId) {
            continue;
        }
        return true;
    }
    return false;
}

int SdlGamepadController::open(const QString& resourcePath) {
    if (isOpen()) {
        qCWarning(m_logBase) << "Gamepad" << getName() << "already open";
        return -1;
    }
    m_pGamepad = SDL_OpenGamepad(m_joystickId);
    if (!m_pGamepad) {
        qCWarning(m_logBase) << "Unable to open gamepad" << getName() << ":" << SDL_GetError();
        return -1;
    }
    m_serial = QString::fromUtf8(SDL_GetGamepadSerial(m_pGamepad));
    m_transport = transportOf(m_pGamepad);
    {
        const int touchpads = SDL_GetNumGamepadTouchpads(m_pGamepad);
        QStringList fingers;
        for (int pad = 0; pad < touchpads; ++pad) {
            fingers << QString::number(SDL_GetNumGamepadTouchpadFingers(m_pGamepad, pad));
        }
        qCInfo(m_logBase) << "Gamepad" << getName() << "touchpads:" << touchpads
                          << (touchpads ? "fingers per pad:" : "") << fingers.join(QStringLiteral("/"));
    }
    m_lastState = State{};
    m_lastReportTime = mixxx::Time::elapsed();
    m_disconnected = false;

    startEngine();
    applyMapping(resourcePath);
    setOpen(true);
    return 0;
}

int SdlGamepadController::close() {
    if (!isOpen()) {
        qCWarning(m_logBase) << "Gamepad" << getName() << "already closed";
        return -1;
    }
    qCInfo(m_logBase) << "Shutting down gamepad" << getName();
    stopEngine();
    SDL_CloseGamepad(m_pGamepad);
    m_pGamepad = nullptr;
    setOpen(false);
    return 0;
}

bool SdlGamepadController::reattach() {
    // Unplugging a pad and plugging it back in (or swapping the cable) gives
    // it a new SDL joystick ID. Adopt the first connected pad of the same
    // model that nobody has opened yet.
    const mixxx::Duration now = mixxx::Time::elapsed();
    if (now - m_lastReattachAttempt < kReattachInterval) {
        return false;
    }
    m_lastReattachAttempt = now;

    int count = 0;
    SDL_JoystickID* pIds = SDL_GetGamepads(&count);
    SDL_JoystickID found = 0;
    for (int i = 0; i < count && !found; ++i) {
        if (SDL_GetGamepadVendorForID(pIds[i]) == m_vendorId &&
                SDL_GetGamepadProductForID(pIds[i]) == m_productId &&
                !SDL_GetGamepadFromID(pIds[i])) {
            found = pIds[i];
        }
    }
    SDL_free(pIds);
    if (!found) {
        return false;
    }
    SDL_Gamepad* pGamepad = SDL_OpenGamepad(found);
    if (!pGamepad) {
        return false;
    }
    SDL_CloseGamepad(m_pGamepad);
    m_pGamepad = pGamepad;
    m_joystickId = found;
    m_transport = transportOf(m_pGamepad);
    qCInfo(m_logBase) << "Gamepad" << getName() << "reconnected";
    return true;
}

bool SdlGamepadController::poll() {
    // One update per poll cycle is enough even with several pads open:
    // SDL_UpdateGamepads() is cheap when nothing changed.
    SDL_UpdateGamepads();
    if (!SDL_GamepadConnected(m_pGamepad)) {
        if (!m_disconnected) {
            m_disconnected = true;
            qCInfo(m_logBase) << "Gamepad" << getName() << "disconnected";
            // Let the mapping see everything at rest (sticks centred,
            // buttons up) so nothing stays held while the pad is gone.
            sendState(State{});
        }
        if (!reattach()) {
            return false;
        }
        m_disconnected = false;
    }

    State state;
    for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT && axis < 6; ++axis) {
        state.axes[axis] = SDL_GetGamepadAxis(m_pGamepad, static_cast<SDL_GamepadAxis>(axis));
    }
    for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT && button < 32; ++button) {
        if (SDL_GetGamepadButton(m_pGamepad, static_cast<SDL_GamepadButton>(button))) {
            state.buttons |= 1u << button;
        }
    }
    const int touchpads = qMin(SDL_GetNumGamepadTouchpads(m_pGamepad), kMaxTouchpads);
    state.touchpads = static_cast<quint8>(touchpads);
    for (int pad = 0; pad < touchpads; ++pad) {
        const int fingers = qMin(SDL_GetNumGamepadTouchpadFingers(m_pGamepad, pad), kMaxFingers);
        for (int finger = 0; finger < fingers; ++finger) {
            bool down = false;
            float x = 0, y = 0, pressure = 0;
            if (!SDL_GetGamepadTouchpadFinger(m_pGamepad, pad, finger, &down, &x, &y, &pressure)) {
                continue;
            }
            Finger& slot = state.fingers[pad * kMaxFingers + finger];
            slot.down = down;
            if (down) {
                // Quantise here so float jitter below the report's
                // resolution doesn't count as a change.
                slot.x = static_cast<quint16>(std::lround(std::clamp(x, 0.0f, 1.0f) * 65535));
                slot.y = static_cast<quint16>(std::lround(std::clamp(y, 0.0f, 1.0f) * 65535));
                slot.pressure = static_cast<quint16>(
                        std::lround(std::clamp(pressure, 0.0f, 1.0f) * 65535));
            }
        }
    }
    return sendState(state);
}

bool SdlGamepadController::sendState(const State& state) {
    if (state == m_lastState) {
        return false;
    }
    m_lastState = state;

    const mixxx::Duration now = mixxx::Time::elapsed();
    const qint64 sinceLast = (now - m_lastReportTime).toIntegerMicros();
    m_lastReportTime = now;

    QByteArray report(kReportSize, '\0');
    char* p = report.data();
    p[0] = static_cast<char>(kReportVersion);
    for (int i = 0; i < 6; ++i) {
        qToLittleEndian<qint16>(state.axes[i], p + 1 + 2 * i);
    }
    qToLittleEndian<quint32>(state.buttons, p + 13);
    qToLittleEndian<quint32>(static_cast<quint32>(qMin<qint64>(sinceLast, UINT32_MAX)), p + 17);
    p[21] = static_cast<char>(state.touchpads);
    for (size_t i = 0; i < state.fingers.size(); ++i) {
        const Finger& finger = state.fingers[i];
        char* f = p + 22 + i * kFingerSize;
        f[0] = finger.down ? 1 : 0;
        qToLittleEndian<quint16>(finger.x, f + 1);
        qToLittleEndian<quint16>(finger.y, f + 3);
        qToLittleEndian<quint16>(finger.pressure, f + 5);
    }

    receive(report, now);
    return true;
}

bool SdlGamepadController::sendBytes(const QByteArray& data) {
    Q_UNUSED(data);
    return false;
}
