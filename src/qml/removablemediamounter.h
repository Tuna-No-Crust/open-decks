#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>

/// Mounts removable drives (USB sticks, SD cards) read-only as they appear,
/// so a rekordbox export is readable the moment the stick is in and pulling
/// it mid-set is as harmless as on a CDJ. The app never writes to a stick.
///
/// Linux only, through UDisks2 on the system bus (what the desktop's own
/// automount uses, so the mount lands under /run/media/$USER where
/// RekordboxFeature looks). Elsewhere it is a no-op: macOS mounts volumes
/// itself and Android goes through its storage framework.
class RemovableMediaMounter : public QObject {
    Q_OBJECT
  public:
    explicit RemovableMediaMounter(QObject* parent = nullptr);

    /// True where UDisks2 is reachable.
    bool isSupported() const {
        return m_supported;
    }
    /// Mount points of the removable filesystems currently known, mounted
    /// by us or already mounted by the system.
    QStringList mountPoints() const;

  public slots:
    /// Look at every removable filesystem and mount the unmounted ones
    /// read-only. Asynchronous: mediaChanged() fires per mount that lands.
    void mountAll();

  signals:
    /// A removable filesystem was mounted or its device went away.
    void mediaChanged();

  private slots:
    void scheduleMountAll();

  private:
    /// Emit mediaChanged() once, from the event loop: mountAll() runs inside
    /// refresh(), and a synchronous emit would re-enter it.
    void notify();
    bool m_supported;
    bool m_notifyPending{false};
    // Name of the QDBusConnection in use (the default system bus, or one
    // opened by socket path when the default address is unusable).
    QString m_busName;
    QTimer m_debounce;
    QSet<QString> m_pending;
    // UDisks2 object path -> mount point
    QHash<QString, QString> m_mounted;
};
