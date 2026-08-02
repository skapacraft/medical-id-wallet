// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.WatchUi;
import Toybox.Lang;

//! Input delegate — single scrollable screen.
//! DOWN / SWIPE_UP → scroll down (see more)
//! UP   / SWIPE_DOWN → scroll up
//! MENU             → reset to top
//! ESC/BACK         → not intercepted; system closes the widget
//!
//! BehaviorDelegate rather than InputDelegate so onSelect() is available:
//! on a widget's base view the system reserves up/down for the widget
//! carousel and the delegate "will never receive either the up/down button
//! or up/down swipe events" (SDK, Connect IQ Basics > App Types). On devices
//! without glances (e.g. fr235) that made pressing DOWN page away to the
//! next widget instead of scrolling — the app appeared to quit. Views pushed
//! with WatchUi.pushView() carry no such restriction, so the base view hands
//! off to a pushed copy of itself on SELECT.
class SafeRunnerDelegate extends WatchUi.BehaviorDelegate {
    private var model      as SafeRunnerModel;
    //! True only for the delegate attached to the widget's base view, where
    //! up/down are owned by the system and SELECT must push the real view.
    private var isBaseView as Boolean;

    function initialize(model as SafeRunnerModel, isBaseView as Boolean) {
        BehaviorDelegate.initialize();
        self.model = model;
        self.isBaseView = isBaseView;
    }

    //! START/ENTER on the base view opens the scrollable view. Returning
    //! false elsewhere leaves the system default behavior untouched.
    function onSelect() as Boolean {
        if (!isBaseView) { return false; }
        model.setScrollOffset(0);
        WatchUi.pushView(new SafeRunnerView(model, false),
                         new SafeRunnerDelegate(model, false),
                         WatchUi.SLIDE_LEFT);
        return true;
    }

    function onKey(keyEvent as KeyEvent) as Boolean {
        var key = keyEvent.getKey();

        if (key == WatchUi.KEY_DOWN) {
            model.scrollUp();
            WatchUi.requestUpdate();
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            model.scrollDown();
            WatchUi.requestUpdate();
            return true;
        }
        if (key == WatchUi.KEY_MENU) {
            model.setScrollOffset(0);
            WatchUi.requestUpdate();
            return true;
        }
        // KEY_ESC intentionally not handled here — returning false lets
        // WatchUi apply its default behavior (close the widget, or pop the
        // pushed view back to the base view).

        return false;
    }

    function onSwipe(swipeEvent as SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();

        if (direction == WatchUi.SWIPE_UP) {
            model.scrollUp();
            WatchUi.requestUpdate();
            return true;
        }
        if (direction == WatchUi.SWIPE_DOWN) {
            model.scrollDown();
            WatchUi.requestUpdate();
            return true;
        }

        return false;
    }

    //! Touch devices: tapping the base view opens the scrollable view, the
    //! same way SELECT does on button devices.
    function onTap(clickEvent as ClickEvent) as Boolean {
        return onSelect();
    }
}
