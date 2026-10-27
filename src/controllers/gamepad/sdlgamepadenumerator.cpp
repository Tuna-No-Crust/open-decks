#include "controllers/gamepad/sdlgamepadenumerator.h"

#include <SDL3/SDL.h>

#include <QByteArray>
#include <QRegularExpression>
#include <QtDebug>

#include "controllers/gamepad/sdlgamepadcontroller.h"
#include "moc_sdlgamepadenumerator.cpp"

namespace {

// Steam hides the raw Steam Deck controller (28de:1205) from games it
// launches (SDL_GAMECONTROLLER_IGNORE_DEVICES) and offers its virtual Xbox
// pad (28de:11ff) instead. The virtual pad has no trackpads, and the FX pads
// are played from them, so swap the two in Steam's list: see the raw pad,
// ignore the virtual one so the sticks aren't read twice. Nothing changes
// when Steam did not hide the Deck's pad (desktop launch, other machines).
void preferRawSteamDeckController() {
    const QString ignore = QString::fromLocal8Bit(qgetenv("SDL_GAMECONTROLLER_IGNORE_DEVICES"));
    static const QRegularExpression kRawDeckPad(
            QStringLiteral("0x28de/0x1205"), QRegularExpression::CaseInsensitiveOption);
    if (!kRawDeckPad.match(ignore).hasMatch()) {
        return;
    }
    QString swapped = ignore;
    swapped.replace(kRawDeckPad, QStringLiteral("0x28de/0x11ff"));
    // Override priority: SDL otherwise lets the environment win over SetHint.
    SDL_SetHintWithPriority(SDL_HINT_GAMECONTROLLER_IGNORE_DEVICES,
            swapped.toUtf8().constData(),
            SDL_HINT_OVERRIDE);
    SDL_SetHintWithPriority(SDL_HINT_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT, "", SDL_HINT_OVERRIDE);
    SDL_SetHintWithPriority(SDL_HINT_JOYSTICK_HIDAPI_STEAMDECK, "1", SDL_HINT_OVERRIDE);
    qInfo() << "Open Decks: Steam hid the Steam Deck controller; using it directly"
            << "(trackpads) and ignoring Steam's virtual pad instead";
}

} // namespace

SdlGamepadEnumerator::SdlGamepadEnumerator()
        : ControllerEnumerator(),
          m_initialized(false) {
    preferRawSteamDeckController();
    // Mixxx has no SDL window, so to SDL the app never has focus. Without this
    // hint SDL zeroes all gamepad input while the app is "in the background".
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    if (!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) {
        qWarning() << "SDL gamepad init failed:" << SDL_GetError();
        return;
    }
    // Nobody drains SDL's event queue; state is polled instead.
    SDL_SetJoystickEventsEnabled(false);
    SDL_SetGamepadEventsEnabled(false);
    m_initialized = true;
}

SdlGamepadEnumerator::~SdlGamepadEnumerator() {
    qDebug() << "Deleting SDL gamepad devices...";
    qDeleteAll(m_devices);
    m_devices.clear();
    if (m_initialized) {
        SDL_QuitSubSystem(SDL_INIT_GAMEPAD);
    }
}

QList<Controller*> SdlGamepadEnumerator::queryDevices() {
    qDebug() << "Scanning SDL gamepads:";
    if (!m_initialized) {
        return {};
    }
    // Also runs SDL's hotplug detection.
    SDL_UpdateGamepads();

    int count = 0;
    SDL_JoystickID* pIds = SDL_GetGamepads(&count);
    for (int i = 0; i < count; ++i) {
        const SDL_JoystickID id = pIds[i];
        if (m_devices.contains(id)) {
            continue;
        }
        QString name = QString::fromUtf8(SDL_GetGamepadNameForID(id));
        if (name.isEmpty()) {
            name = QStringLiteral("Gamepad");
        }
        // Device names key the config, so two identical pads need distinct
        // names, but the first one keeps the plain name across sessions.
        const QString baseName = name;
        for (int n = 2; std::any_of(m_devices.cbegin(),
                                m_devices.cend(),
                                [&name](const Controller* pDevice) {
                                    return pDevice->getName() == name;
                                });
                ++n) {
            name = QStringLiteral("%1 #%2").arg(baseName).arg(n);
        }
        qDebug() << "  Found" << name;
        m_devices.insert(id,
                new SdlGamepadController(id,
                        name,
                        SDL_GetGamepadVendorForID(id),
                        SDL_GetGamepadProductForID(id)));
    }
    SDL_free(pIds);
    return m_devices.values();
}
