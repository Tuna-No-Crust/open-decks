#pragma once

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QString>
#include <QTimer>
#include <memory>
#include <vector>

#include "control/controlobject.h"
#include "control/controlpushbutton.h"
#include "coreservices.h"
#include "qmlautoreload.h"
#include "util/parented_ptr.h"

class ControlProxy;
class ControlPushButton;
class GuiTick;
class VisualsManager;
class QQuickWindow;
#if defined(Q_OS_ANDROID)
class APerformanceHintSession;
#endif

namespace mixxx {
namespace qml {

class QmlApplication : public QObject {
    Q_OBJECT
  public:
    QmlApplication(
            QApplication* app,
            std::shared_ptr<CoreServices> pCoreServices,
            const QString& mainQmlFilePath = QString());
    ~QmlApplication() override;

    bool isReady() const {
        return m_loadSucceeded;
    }

  public slots:
    bool loadQml(const QString& path);

  private slots:
    void slotFrameSwapped();
    void slotWindowChanged(QQuickWindow* window);

  private:
    void registerImageProvider();
    void setupSpinnyCoverControls();
    void updateSpinnyCoverControls();

    std::shared_ptr<CoreServices> m_pCoreServices;
    std::unique_ptr<::VisualsManager> m_visualsManager;
    std::unique_ptr<GuiTick> m_pGuiTick;
    QTimer m_guiTickTimer;

    parented_ptr<ControlProxy> m_pShowSpinny;
    parented_ptr<ControlProxy> m_pShowCover;
    std::unique_ptr<ControlPushButton> m_pShowSpinnyAndOrCover;
    std::unique_ptr<ControlPushButton> m_pSelectBigSpinnyCover;
    std::unique_ptr<ControlPushButton> m_pShowSmallSpinnyCover;
    std::unique_ptr<ControlPushButton> m_pShowBigSpinnyCover;
    std::unique_ptr<ControlPushButton> m_pWaveformOverviewType;
    // Handheld UI controls, shared with the gamepad mapping (see the OpenDecks QML module):
    //   [OpenDecks] focus    0 none, 1 deck 1, 2 deck 2, 3 the top bar (tabs)
    //   [OpenDecks] tab      0 Perform, 1 Library, 2 FX
    //   [OpenDecks] tab_next / tab_prev   push buttons the controller presses
    //   [OpenDecks] fxN_touch / fxN_x / fxN_y   a controller touchpad playing
    //            deck N's FX XY pad: touch 0/1, x/y 0..1 (y up), set by
    //            the mapping and acted on by FxUnitPanel like a finger
    //   [OpenDecks] vinylN   deck N's jog is in vinyl (scratch) mode, 0/1;
    //            toggled by the deck panel's VINYL badge, read by the mapping
    std::unique_ptr<ControlObject> m_pOpenDecksFocus;
    std::unique_ptr<ControlObject> m_pOpenDecksTab;
    std::unique_ptr<ControlPushButton> m_pOpenDecksTabNext;
    std::unique_ptr<ControlPushButton> m_pOpenDecksTabPrev;
    std::vector<std::unique_ptr<ControlObject>> m_openDecksControls;

    QString m_mainFilePath;

    std::unique_ptr<QQmlApplicationEngine> m_pAppEngine;
    bool m_ownsWaveformWidgetFactory{false};
    bool m_loadSucceeded;
    QmlAutoReload m_autoReload;

#if defined(Q_OS_ANDROID)
    // The following are necessary to implement the performance manager
    // (https://developer.android.com/ndk/reference/group/a-performance-hint)
    // This helps the system automatically adjust performance and prevent frame
    // drops
    PerformanceTimer m_frameTimer;
    APerformanceHintSession* m_perfSession;
#endif
};

} // namespace qml
} // namespace mixxx
