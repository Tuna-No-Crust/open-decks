#pragma once

#include <QHash>

#include "controllers/controllerenumerator.h"

/// Locate game controllers through SDL's gamepad API (desktop platforms).
///
/// Owns SDL's gamepad subsystem for its lifetime. SDL events are disabled:
/// the controllers pull state with SDL_UpdateGamepads() from the
/// ControllerManager poll loop instead, so all SDL calls stay on that thread.
class SdlGamepadEnumerator : public ControllerEnumerator {
    Q_OBJECT
  public:
    SdlGamepadEnumerator();
    ~SdlGamepadEnumerator() override;

    QList<Controller*> queryDevices() override;

  private:
    bool m_initialized;
    // keyed by SDL_JoystickID, which is unique for the lifetime of a connection
    QHash<quint32, Controller*> m_devices;
};
