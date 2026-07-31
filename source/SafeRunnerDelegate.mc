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
class SafeRunnerDelegate extends WatchUi.InputDelegate {
    private var model as SafeRunnerModel;

    function initialize(model as SafeRunnerModel) {
        InputDelegate.initialize();
        self.model = model;
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
        // WatchUi apply its default behavior (close the widget).

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
}
