#include "qml/qmlrekordboxproxy.h"

#include <QColor>
#include <QDir>
#include <QtDebug>
#include <functional>

#include "library/basetracktablemodel.h"
#include "library/library.h"
#include "library/rekordbox/rekordboxfeature.h"
#include "qml/removablemediamounter.h"
#include "library/trackmodel.h"
#include "library/treeitem.h"
#include "library/treeitemmodel.h"
#include "mixer/playermanager.h"
#include "moc_qmlrekordboxproxy.cpp"
#include "qml/qmlconfigproxy.h"
#include "qml/qmllibraryproxy.h"
#include "track/track.h"

namespace mixxx {
namespace qml {

namespace {

const ConfigKey kExtraFoldersKey(QStringLiteral("[OpenDecks]"), QStringLiteral("RekordboxFolders"));
// The group was [DJApp] until 2026-10-27; read it once so existing profiles
// keep their folders.
const ConfigKey kLegacyExtraFoldersKey(QStringLiteral("[DJApp]"), QStringLiteral("RekordboxFolders"));
const QString kDeviceFlag = QStringLiteral("::isRecordboxDevice::");
const QString kPlaylistPathDelimiter = QStringLiteral("-->");

QString formatDuration(int seconds) {
    seconds = qMax(0, seconds);
    return QStringLiteral("%1:%2").arg(seconds / 60).arg(seconds % 60, 2, 10, QChar('0'));
}

} // namespace

// ---- QmlRekordboxTrackModel ------------------------------------------------

QmlRekordboxTrackModel::QmlRekordboxTrackModel(QObject* parent)
        : QIdentityProxyModel(parent) {
    connect(this, &QAbstractItemModel::modelReset, this, &QmlRekordboxTrackModel::countChanged);
    connect(this, &QAbstractItemModel::rowsInserted, this, &QmlRekordboxTrackModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &QmlRekordboxTrackModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &QmlRekordboxTrackModel::countChanged);
}

void QmlRekordboxTrackModel::setSourceModel(QAbstractItemModel* pModel) {
    if (pModel == sourceModel()) {
        return;
    }
    QIdentityProxyModel::setSourceModel(pModel);
    emit countChanged();
}

int QmlRekordboxTrackModel::count() const {
    return rowCount();
}

QHash<int, QByteArray> QmlRekordboxTrackModel::roleNames() const {
    return {
            {TitleRole, "title"},
            {ArtistRole, "artist"},
            {AlbumRole, "album"},
            {BpmRole, "bpm"},
            {KeyRole, "key"},
            {DurationRole, "duration"},
            {ColorRole, "color"},
            {LocationRole, "location"},
            {HotCuesRole, "hotcues"},
            {MemoryCuesRole, "memcues"},
    };
}

int QmlRekordboxTrackModel::column(int role) const {
    const auto* pTableModel = dynamic_cast<const BaseSqlTableModel*>(sourceModel());
    if (!pTableModel) {
        return -1;
    }
    switch (role) {
    case TitleRole:
        return pTableModel->fieldIndex(QStringLiteral("title"));
    case ArtistRole:
        return pTableModel->fieldIndex(QStringLiteral("artist"));
    case AlbumRole:
        return pTableModel->fieldIndex(QStringLiteral("album"));
    case BpmRole:
        return pTableModel->fieldIndex(QStringLiteral("bpm"));
    case KeyRole:
        return pTableModel->fieldIndex(QStringLiteral("key"));
    case DurationRole:
        return pTableModel->fieldIndex(QStringLiteral("duration"));
    case ColorRole:
        return pTableModel->fieldIndex(QStringLiteral("color"));
    case LocationRole:
        return pTableModel->fieldIndex(QStringLiteral("location"));
    case HotCuesRole:
        return pTableModel->fieldIndex(QStringLiteral("hotcue_count"));
    case MemoryCuesRole:
        return pTableModel->fieldIndex(QStringLiteral("memcue_count"));
    default:
        return -1;
    }
}

QVariant QmlRekordboxTrackModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || !sourceModel()) {
        return QVariant();
    }
    const int col = column(role);
    if (col < 0) {
        return QVariant();
    }
    const QModelIndex src = sourceModel()->index(index.row(), col);
    switch (role) {
    case ColorRole: {
        // The raw column value is an RGB integer; null, -1 and 0 (black,
        // which rekordbox never assigns) mean no colour.
        const QVariant raw = sourceModel()->data(src, Qt::EditRole);
        bool ok = false;
        const int rgb = raw.toInt(&ok);
        if (!ok || rgb <= 0) {
            return QColor(Qt::transparent);
        }
        return QColor::fromRgb(static_cast<QRgb>(rgb));
    }
    case DurationRole: {
        const QVariant raw = sourceModel()->data(src, Qt::EditRole);
        bool ok = false;
        const double seconds = raw.toDouble(&ok);
        if (ok) {
            return formatDuration(static_cast<int>(seconds));
        }
        return sourceModel()->data(src, Qt::DisplayRole);
    }
    case HotCuesRole:
    case MemoryCuesRole:
        return sourceModel()->data(src, Qt::EditRole).toInt();
    case BpmRole: {
        const QVariant raw = sourceModel()->data(src, Qt::EditRole);
        bool ok = false;
        const double bpm = raw.toDouble(&ok);
        if (ok && bpm > 0) {
            return QString::number(bpm, 'f', 2);
        }
        return QString();
    }
    default:
        return sourceModel()->data(src, Qt::DisplayRole);
    }
}

void QmlRekordboxTrackModel::search(const QString& text) {
    auto* pTrackModel = dynamic_cast<TrackModel*>(sourceModel());
    if (pTrackModel) {
        pTrackModel->search(text);
    }
}

void QmlRekordboxTrackModel::sortBy(const QString& role, bool descending) {
    static const QHash<QString, int> roles = {
            {QStringLiteral("title"), TitleRole},
            {QStringLiteral("artist"), ArtistRole},
            {QStringLiteral("album"), AlbumRole},
            {QStringLiteral("bpm"), BpmRole},
            {QStringLiteral("key"), KeyRole},
            {QStringLiteral("duration"), DurationRole},
    };
    const int col = column(roles.value(role, -1));
    if (col >= 0 && sourceModel()) {
        sourceModel()->sort(col, descending ? Qt::DescendingOrder : Qt::AscendingOrder);
    }
}

// ---- QmlRekordboxProxy -----------------------------------------------------

QmlRekordboxProxy::QmlRekordboxProxy(QObject* parent)
        : QObject(parent),
          m_pFeature(nullptr),
          m_pMounter(new RemovableMediaMounter(this)),
          m_pTracks(new QmlRekordboxTrackModel(this)) {
    Library* pLibrary = QmlLibraryProxy::get();
    if (pLibrary) {
        m_pFeature = pLibrary->rekordboxFeature();
    }
    if (!m_pFeature) {
        qWarning() << "QmlRekordboxProxy: rekordbox feature is not available";
        return;
    }

    UserSettingsPointer pConfig = QmlConfigProxy::get();
    if (pConfig) {
        QString stored = pConfig->getValueString(kExtraFoldersKey);
        if (stored.isEmpty()) {
            stored = pConfig->getValueString(kLegacyExtraFoldersKey);
            if (!stored.isEmpty()) {
                pConfig->setValue(kExtraFoldersKey, stored);
                pConfig->remove(kLegacyExtraFoldersKey);
            }
        }
        m_extraFolders = stored.split(QChar(';'), Qt::SkipEmptyParts);
    }
    applyDeviceFolders();

    connect(m_pMounter,
            &RemovableMediaMounter::mediaChanged,
            this,
            &QmlRekordboxProxy::slotMediaChanged);
    connect(m_pFeature,
            &LibraryFeature::featureLoadingFinished,
            this,
            &QmlRekordboxProxy::slotDevicesFound);
    connect(m_pFeature,
            &LibraryFeature::showTrackModel,
            this,
            &QmlRekordboxProxy::slotShowTrackModel);

    refresh();
}

// static
QmlRekordboxProxy* QmlRekordboxProxy::create(QQmlEngine* pQmlEngine, QJSEngine* pJsEngine) {
    Q_UNUSED(pJsEngine);
    auto* pProxy = new QmlRekordboxProxy();
    QQmlEngine::setObjectOwnership(pProxy, QQmlEngine::CppOwnership);
    pProxy->setParent(pQmlEngine);
    return pProxy;
}

QVariantList QmlRekordboxProxy::devices() const {
    QVariantList list;
    if (!m_pFeature) {
        return list;
    }
    TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
    if (!pRoot) {
        return list;
    }
    for (TreeItem* pItem : pRoot->children()) {
        const QList<QVariant> data = pItem->getData().toList();
        if (data.size() < 2) {
            continue;
        }
        QVariantMap device;
        device.insert(QStringLiteral("name"), pItem->getLabel());
        device.insert(QStringLiteral("path"), data[0].toString());
        device.insert(QStringLiteral("parsed"), data[1].toString() != kDeviceFlag);
        list.append(device);
    }
    return list;
}

void QmlRekordboxProxy::refresh() {
    if (!m_pFeature) {
        return;
    }
    // Sticks plugged in since the last look get mounted (read-only) first;
    // each mount that lands triggers another refresh through mediaChanged.
    m_pMounter->mountAll();
    setLoading(true);
    m_pFeature->activate();
}

void QmlRekordboxProxy::slotDevicesFound() {
    setLoading(false);
    emit devicesChanged();
    // The current device may have gone (stick pulled).
    if (!m_currentDevice.isEmpty()) {
        TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
        if (!findItem(pRoot, m_currentDevice)) {
            m_currentDevice.clear();
            m_currentPlaylist.clear();
            m_playlists.clear();
            m_pTracks->setSourceModel(nullptr);
            emit playlistsChanged();
            emit currentChanged();
        }
    }
}

TreeItem* QmlRekordboxProxy::findItem(TreeItem* pParent, const QString& path) const {
    if (!pParent) {
        return nullptr;
    }
    for (TreeItem* pChild : pParent->children()) {
        const QList<QVariant> data = pChild->getData().toList();
        if (!data.isEmpty() && data[0].toString() == path) {
            return pChild;
        }
        TreeItem* pFound = findItem(pChild, path);
        if (pFound) {
            return pFound;
        }
    }
    return nullptr;
}

QModelIndex QmlRekordboxProxy::indexOf(TreeItem* pItem) const {
    // Walk up to the root collecting rows, then down again building indexes.
    QList<int> rows;
    TreeItem* pCursor = pItem;
    TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
    while (pCursor && pCursor != pRoot) {
        rows.prepend(pCursor->parentRow());
        pCursor = pCursor->parent();
    }
    QModelIndex index;
    for (int row : rows) {
        index = m_pFeature->sidebarModel()->index(row, 0, index);
    }
    return index;
}

void QmlRekordboxProxy::selectDevice(const QString& path) {
    if (!m_pFeature) {
        return;
    }
    TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
    TreeItem* pDevice = findItem(pRoot, path);
    if (!pDevice) {
        qWarning() << "QmlRekordboxProxy: no rekordbox device at" << path;
        return;
    }
    const QList<QVariant> data = pDevice->getData().toList();
    const bool parsed = data.size() >= 2 && data[1].toString() != kDeviceFlag;
    m_currentDevice = path;
    m_currentPlaylist = path;
    if (!parsed) {
        // activateChild() parses the export on a worker thread and shows the
        // device's "all tracks" playlist when done (slotShowTrackModel).
        m_pendingDevice = path;
        setLoading(true);
        m_playlists.clear();
        emit playlistsChanged();
    } else {
        rebuildPlaylists();
    }
    emit currentChanged();
    m_pFeature->activateChild(indexOf(pDevice));
}

void QmlRekordboxProxy::selectPlaylist(const QString& path) {
    if (!m_pFeature || m_currentDevice.isEmpty()) {
        return;
    }
    TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
    TreeItem* pItem = findItem(pRoot, path);
    if (!pItem) {
        qWarning() << "QmlRekordboxProxy: no playlist" << path;
        return;
    }
    m_currentPlaylist = path;
    emit currentChanged();
    m_pFeature->activateChild(indexOf(pItem));
}

void QmlRekordboxProxy::slotShowTrackModel(QAbstractItemModel* pModel) {
    // The SQL table model only runs its query on select(), which the classic
    // table view does when a model is shown.
    auto* pTrackModel = dynamic_cast<TrackModel*>(pModel);
    if (pTrackModel) {
        pTrackModel->select();
    }
    m_pTracks->setSourceModel(pModel);
    if (!m_pendingDevice.isEmpty()) {
        // The device's export has been parsed: its playlists exist now.
        m_pendingDevice.clear();
        setLoading(false);
        rebuildPlaylists();
        emit devicesChanged();
    }
    emit m_pTracks->countChanged();
}

void QmlRekordboxProxy::rebuildPlaylists() {
    m_playlists.clear();
    TreeItem* pRoot = m_pFeature->sidebarModel()->getRootItem();
    TreeItem* pDevice = findItem(pRoot, m_currentDevice);
    if (pDevice) {
        std::function<void(TreeItem*, int)> walk = [&](TreeItem* pParent, int depth) {
            for (TreeItem* pChild : pParent->children()) {
                const QList<QVariant> data = pChild->getData().toList();
                if (data.isEmpty()) {
                    continue;
                }
                QVariantMap entry;
                entry.insert(QStringLiteral("name"), pChild->getLabel());
                entry.insert(QStringLiteral("path"), data[0].toString());
                entry.insert(QStringLiteral("depth"), depth);
                entry.insert(QStringLiteral("folder"), pChild->hasChildren());
                m_playlists.append(entry);
                walk(pChild, depth + 1);
            }
        };
        walk(pDevice, 0);
    }
    emit playlistsChanged();
}

void QmlRekordboxProxy::loadTrack(int row, int deck) {
    QAbstractItemModel* pSource = m_pTracks->sourceModel();
    auto* pTrackModel = dynamic_cast<TrackModel*>(pSource);
    if (!pTrackModel || row < 0 || row >= pSource->rowCount()) {
        return;
    }
    // RekordboxPlaylistModel::getTrack attaches the ANLZ beatgrid and cues.
    TrackPointer pTrack = pTrackModel->getTrack(pSource->index(row, 0));
    if (!pTrack) {
        emit error(tr("Track %1 could not be opened").arg(row + 1));
        return;
    }
    Library* pLibrary = QmlLibraryProxy::get();
    if (!pLibrary) {
        return;
    }
    const QString group = QStringLiteral("[Channel%1]").arg(deck);
#ifdef __STEM__
    pLibrary->slotLoadTrackToPlayer(pTrack, group, mixxx::StemChannelSelection(), false);
#else
    pLibrary->slotLoadTrackToPlayer(pTrack, group, false);
#endif
}

void QmlRekordboxProxy::addFolder(const QString& path) {
    const QString clean = QDir::cleanPath(path);
    if (clean.isEmpty() || m_extraFolders.contains(clean)) {
        return;
    }
    m_extraFolders.append(clean);
    saveExtraFolders();
    refresh();
}

void QmlRekordboxProxy::removeFolder(const QString& path) {
    if (m_extraFolders.removeAll(QDir::cleanPath(path)) > 0) {
        saveExtraFolders();
        refresh();
    }
}

void QmlRekordboxProxy::saveExtraFolders() {
    UserSettingsPointer pConfig = QmlConfigProxy::get();
    if (pConfig) {
        pConfig->setValue(kExtraFoldersKey, m_extraFolders.join(QChar(';')));
    }
    applyDeviceFolders();
    emit extraFoldersChanged();
}

void QmlRekordboxProxy::applyDeviceFolders() {
    // Folders the user added plus whatever the mounter has put up; the
    // feature drops duplicates of drives it finds on its own.
    RekordboxFeature::setExtraDeviceFolders(m_extraFolders + m_pMounter->mountPoints());
}

void QmlRekordboxProxy::slotMediaChanged() {
    applyDeviceFolders();
    refresh();
}

void QmlRekordboxProxy::setLoading(bool loading) {
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

} // namespace qml
} // namespace mixxx
