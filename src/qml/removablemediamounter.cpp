#include "qml/removablemediamounter.h"

#include <QtDebug>
#include <QtGlobal>

#include "moc_removablemediamounter.cpp"

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
#define OPENDECKS_UDISKS 1
#endif

#ifdef OPENDECKS_UDISKS
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QFile>
#include <QMap>
#include <QVariantMap>

// a{sa{sv}}: interface name -> properties, as ObjectManager hands them out.
using InterfaceMap = QMap<QString, QVariantMap>;
// a{oa{sa{sv}}}: the GetManagedObjects reply.
using ManagedObjects = QMap<QDBusObjectPath, InterfaceMap>;
Q_DECLARE_METATYPE(InterfaceMap)
Q_DECLARE_METATYPE(ManagedObjects)

namespace {

const QString kService = QStringLiteral("org.freedesktop.UDisks2");
const QString kManagerPath = QStringLiteral("/org/freedesktop/UDisks2");
const QString kObjectManager = QStringLiteral("org.freedesktop.DBus.ObjectManager");
const QString kBlockIface = QStringLiteral("org.freedesktop.UDisks2.Block");
const QString kFilesystemIface = QStringLiteral("org.freedesktop.UDisks2.Filesystem");
const QString kDriveIface = QStringLiteral("org.freedesktop.UDisks2.Drive");
constexpr int kDebounceMs = 700;
const QString kBusName = QStringLiteral("opendecks-system-bus");

QStringList mountPointsOf(const QVariant& value) {
    // aay, each entry a NUL-terminated path.
    QStringList list;
    const auto arrays = qdbus_cast<QList<QByteArray>>(value);
    for (QByteArray bytes : arrays) {
        while (bytes.endsWith('\0')) {
            bytes.chop(1);
        }
        if (!bytes.isEmpty()) {
            list << QString::fromLocal8Bit(bytes);
        }
    }
    return list;
}

bool isRemovableDrive(const QDBusConnection& bus, const QDBusObjectPath& drivePath) {
    if (drivePath.path().isEmpty() || drivePath.path() == QLatin1String("/")) {
        return false; // loop devices and the like have no drive
    }
    QDBusInterface drive(kService, drivePath.path(), kDriveIface, bus);
    if (!drive.isValid()) {
        return false;
    }
    return drive.property("Removable").toBool() ||
            drive.property("MediaRemovable").toBool() ||
            drive.property("ConnectionBus").toString() == QLatin1String("usb");
}

} // namespace
#endif

RemovableMediaMounter::RemovableMediaMounter(QObject* parent)
        : QObject(parent),
          m_supported(false) {
    m_debounce.setSingleShot(true);
    connect(&m_debounce, &QTimer::timeout, this, &RemovableMediaMounter::mountAll);
#ifdef OPENDECKS_UDISKS
    m_debounce.setInterval(kDebounceMs);
    qDBusRegisterMetaType<InterfaceMap>();
    qDBusRegisterMetaType<ManagedObjects>();
    // The AppImage bundles libdbus-1 from the vcpkg dependency build, whose
    // compiled-in default system bus address is a path on the build machine
    // (the session bus works because its address is in the environment), and
    // libdbus fixes the addresses the first time any bus is opened, which
    // Mixxx does long before this. So open the system bus by its socket.
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected() && qEnvironmentVariableIsEmpty("DBUS_SYSTEM_BUS_ADDRESS")) {
        for (const char* path : {"/run/dbus/system_bus_socket", "/var/run/dbus/system_bus_socket"}) {
            if (QFile::exists(QLatin1String(path))) {
                bus = QDBusConnection::connectToBus(
                        QStringLiteral("unix:path=") + QLatin1String(path), kBusName);
                break;
            }
        }
    }
    if (!bus.isConnected()) {
        qInfo() << "Open Decks: no system D-Bus, sticks must be mounted by hand:"
                << bus.lastError().name() << bus.lastError().message();
        return;
    }
    m_busName = bus.name();
    QDBusConnectionInterface* pBusIface = bus.interface();
    const bool available = pBusIface->isServiceRegistered(kService).value() ||
            pBusIface->activatableServiceNames().value().contains(kService);
    if (!available) {
        qInfo() << "Open Decks: UDisks2 is not available, sticks must be mounted by hand";
        return;
    }
    m_supported = true;
    // Both hotplug signals just re-run the full look (several InterfacesAdded
    // arrive per stick: drive, block, partition, filesystem), debounced. The
    // slot takes no arguments; QtDBus drops the signal's.
    bus.connect(kService,
            kManagerPath,
            kObjectManager,
            QStringLiteral("InterfacesAdded"),
            this,
            SLOT(scheduleMountAll()));
    bus.connect(kService,
            kManagerPath,
            kObjectManager,
            QStringLiteral("InterfacesRemoved"),
            this,
            SLOT(scheduleMountAll()));
    qInfo() << "Open Decks: mounting removable drives read-only through UDisks2";
#endif
}

QStringList RemovableMediaMounter::mountPoints() const {
    return m_mounted.values();
}

void RemovableMediaMounter::notify() {
    if (m_notifyPending) {
        return;
    }
    m_notifyPending = true;
    QTimer::singleShot(0, this, [this] {
        m_notifyPending = false;
        emit mediaChanged();
    });
}

void RemovableMediaMounter::scheduleMountAll() {
    if (m_supported) {
        m_debounce.start();
    }
}

void RemovableMediaMounter::mountAll() {
#ifdef OPENDECKS_UDISKS
    if (!m_supported) {
        return;
    }
    const QDBusConnection bus(m_busName);
    QDBusInterface manager(kService, kManagerPath, kObjectManager, bus);
    QDBusReply<ManagedObjects> reply = manager.call(QStringLiteral("GetManagedObjects"));
    if (!reply.isValid()) {
        qWarning() << "Open Decks: UDisks2 GetManagedObjects failed:" << reply.error().message();
        return;
    }
    const ManagedObjects objects = reply.value();
    QSet<QString> present;
    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        const QString path = it.key().path();
        const InterfaceMap& ifaces = it.value();
        if (!ifaces.contains(kFilesystemIface) || !ifaces.contains(kBlockIface)) {
            continue;
        }
        const QVariantMap block = ifaces.value(kBlockIface);
        if (block.value(QStringLiteral("HintIgnore")).toBool() ||
                block.value(QStringLiteral("HintSystem")).toBool()) {
            continue;
        }
        if (!isRemovableDrive(bus, qdbus_cast<QDBusObjectPath>(block.value(QStringLiteral("Drive"))))) {
            continue;
        }
        present.insert(path);
        const QStringList mounted = mountPointsOf(
                ifaces.value(kFilesystemIface).value(QStringLiteral("MountPoints")));
        if (!mounted.isEmpty()) {
            // Mounted already (by the desktop, or by us earlier): just know it.
            if (m_mounted.value(path) != mounted.first()) {
                m_mounted.insert(path, mounted.first());
                notify();
            }
            continue;
        }
        if (m_pending.contains(path)) {
            continue;
        }
        m_pending.insert(path);
        QByteArray deviceBytes = qdbus_cast<QByteArray>(block.value(QStringLiteral("Device")));
        while (deviceBytes.endsWith('\0')) {
            deviceBytes.chop(1); // ay, NUL-terminated like the mount points
        }
        const QString device = QString::fromLocal8Bit(deviceBytes);
        auto* pFs = new QDBusInterface(kService, path, kFilesystemIface, bus, this);
        QVariantMap options;
        options.insert(QStringLiteral("options"), QStringLiteral("ro"));
        options.insert(QStringLiteral("auth.no_user_interaction"), true);
        auto* pWatcher = new QDBusPendingCallWatcher(
                pFs->asyncCall(QStringLiteral("Mount"), options), this);
        connect(pWatcher,
                &QDBusPendingCallWatcher::finished,
                this,
                [this, path, device, pFs](QDBusPendingCallWatcher* pDone) {
                    const QDBusPendingReply<QString> result = *pDone;
                    m_pending.remove(path);
                    if (result.isError()) {
                        qWarning() << "Open Decks: could not mount" << device
                                   << "read-only:" << result.error().message();
                    } else {
                        qInfo() << "Open Decks: mounted" << device
                                << "read-only at" << result.value();
                        m_mounted.insert(path, result.value());
                        notify();
                    }
                    pDone->deleteLater();
                    pFs->deleteLater();
                });
    }
    // Devices that went away (stick pulled: UDisks drops the object).
    bool removed = false;
    for (auto it = m_mounted.begin(); it != m_mounted.end();) {
        if (!present.contains(it.key())) {
            qInfo() << "Open Decks: removable drive at" << it.value() << "is gone";
            it = m_mounted.erase(it);
            removed = true;
        } else {
            ++it;
        }
    }
    if (removed) {
        notify();
    }
#endif
}
