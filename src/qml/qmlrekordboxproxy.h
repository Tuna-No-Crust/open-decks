#pragma once

#include <QIdentityProxyModel>
#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QVariantList>

class RekordboxFeature;
class RemovableMediaMounter;
class QAbstractItemModel;
class TreeItem;

namespace mixxx {
namespace qml {

/// The tracks of the selected rekordbox playlist as a flat list model with
/// named roles, over the feature's own playlist table model.
class QmlRekordboxTrackModel : public QIdentityProxyModel {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(int count READ count NOTIFY countChanged)
  public:
    enum Roles {
        TitleRole = Qt::UserRole + 1,
        ArtistRole,
        AlbumRole,
        BpmRole,
        KeyRole,
        DurationRole,
        ColorRole,
        LocationRole,
        HotCuesRole,
        MemoryCuesRole,
    };
    Q_ENUM(Roles)

    explicit QmlRekordboxTrackModel(QObject* parent = nullptr);

    void setSourceModel(QAbstractItemModel* pModel) override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const;

    /// Filter the list (title, artist, album... as the classic UI searches).
    Q_INVOKABLE void search(const QString& text);
    /// Sort by one of the role names ("bpm", "title"...), ascending or not.
    Q_INVOKABLE void sortBy(const QString& role, bool descending);

  signals:
    void countChanged();

  private:
    int column(int role) const;
};

/// The rekordbox library for the touch UI: which sticks (or copied folders)
/// hold an export, their playlists, the selected playlist's tracks, and
/// loading a track to a deck *with* its rekordbox cues and beatgrid.
/// Drives Mixxx's own RekordboxFeature instead of the classic sidebar.
class QmlRekordboxProxy : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Rekordbox)
    QML_SINGLETON
    /// Whether rekordbox support is available at all (feature enabled).
    Q_PROPERTY(bool available READ available CONSTANT)
    /// [{name, path, parsed}] — every mounted stick / folder with an export.
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    /// [{name, path, depth, folder}] of the current device, tree order.
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(QString currentDevice READ currentDevice NOTIFY currentChanged)
    Q_PROPERTY(QString currentPlaylist READ currentPlaylist NOTIFY currentChanged)
    /// True while sticks are being looked for or an export is being parsed.
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(mixxx::qml::QmlRekordboxTrackModel* tracks READ tracks CONSTANT)
    /// Folders on internal storage holding an export (persisted).
    Q_PROPERTY(QStringList extraFolders READ extraFolders NOTIFY extraFoldersChanged)
  public:
    explicit QmlRekordboxProxy(QObject* parent = nullptr);

    static QmlRekordboxProxy* create(QQmlEngine* pQmlEngine, QJSEngine* pJsEngine);

    bool available() const {
        return m_pFeature != nullptr;
    }
    QVariantList devices() const;
    QVariantList playlists() const {
        return m_playlists;
    }
    QString currentDevice() const {
        return m_currentDevice;
    }
    QString currentPlaylist() const {
        return m_currentPlaylist;
    }
    bool loading() const {
        return m_loading;
    }
    QmlRekordboxTrackModel* tracks() const {
        return m_pTracks;
    }
    QStringList extraFolders() const {
        return m_extraFolders;
    }

    /// Look for sticks again (after plugging one in).
    Q_INVOKABLE void refresh();
    /// Parse a device's export (first time) and show all its tracks.
    Q_INVOKABLE void selectDevice(const QString& path);
    /// Show one playlist of the current device (its path from `playlists`).
    Q_INVOKABLE void selectPlaylist(const QString& path);
    /// Load the track at `row` of `tracks` into deck 1 or 2, keeping its
    /// rekordbox hot cues, memory cues and beatgrid.
    Q_INVOKABLE void loadTrack(int row, int deck);
    Q_INVOKABLE void addFolder(const QString& path);
    Q_INVOKABLE void removeFolder(const QString& path);

  signals:
    void devicesChanged();
    void playlistsChanged();
    void currentChanged();
    void loadingChanged();
    void extraFoldersChanged();
    /// A device's export failed to parse (shown as a message in the UI).
    void error(const QString& message);

  private slots:
    void slotDevicesFound();
    void slotShowTrackModel(QAbstractItemModel* pModel);
    void slotMediaChanged();

  private:
    TreeItem* findItem(TreeItem* pParent, const QString& path) const;
    QModelIndex indexOf(TreeItem* pItem) const;
    void rebuildPlaylists();
    void setLoading(bool loading);
    void saveExtraFolders();
    void applyDeviceFolders();

    RekordboxFeature* m_pFeature;
    RemovableMediaMounter* m_pMounter;
    QmlRekordboxTrackModel* m_pTracks;
    QVariantList m_playlists;
    QString m_currentDevice;
    QString m_currentPlaylist;
    QString m_pendingDevice;
    QStringList m_extraFolders;
    bool m_loading{false};
};

} // namespace qml
} // namespace mixxx
