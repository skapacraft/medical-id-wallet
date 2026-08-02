// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.System;

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

    //! On a glance-capable device the widget is launched from the glance
    //! list, and the SDK states the base view then "don't have the input
    //! restrictions regularly applied" — so scrolling works immediately and
    //! the initial view is the interactive one. Where glances don't exist
    //! (fr235 and other pre-3.1.0 devices) the widget sits in the carousel,
    //! up/down belong to the system, and the initial view must act as a base
    //! view that pushes the scrollable view on SELECT instead.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var m = getModel();
        var restricted = isBaseViewInputRestricted();
        return [new SafeRunnerView(m, restricted), new SafeRunnerDelegate(m, restricted)];
    }

    private function isBaseViewInputRestricted() as Boolean {
        var settings = System.getDeviceSettings();
        if (!(settings has :isGlanceModeEnabled)) { return true; }
        var enabled = settings.isGlanceModeEnabled;
        return !(enabled == true);
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
