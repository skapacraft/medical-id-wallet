// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//! SafeRunner ICE Wallet main application class.
//! Annotated (:glance) so the app can run in the glance carousel on modern
//! devices (fr165/255/265/955/965 and later); on API level 4.0.0+ a widget
//! without a glance view would not appear in the glance list at all.
(:glance)
class SafeRunnerApp extends Application.AppBase {
    private var model as SafeRunnerModel?;

    function initialize() {
        AppBase.initialize();
    }

    //! Lazily create the shared data model
    private function getModel() as SafeRunnerModel {
        if (model == null) {
            model = new SafeRunnerModel();
        }
        return model as SafeRunnerModel;
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var m = getModel();
        return [new SafeRunnerView(m), new SafeRunnerDelegate(m)];
    }

    //! The glance builds nothing beyond its own view — it reads the single
    //! property it displays itself, so the full model (and the large
    //! free-text fields it loads) never enters the glance memory budget.
    (:glance)
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new SafeRunnerGlanceView()];
    }

    //! Settings changed from Garmin Connect Mobile: reload and redraw
    function onSettingsChanged() as Void {
        if (model != null) {
            (model as SafeRunnerModel).loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
