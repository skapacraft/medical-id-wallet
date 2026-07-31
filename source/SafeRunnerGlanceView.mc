// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;

//! Compact summary shown in the glance carousel: the "ICE" tag plus the
//! blood type when configured. Uses no localized resources on purpose,
//! keeping the glance memory footprint minimal ("ICE" is universal).
//!
//! Reads the one property it needs directly instead of sharing
//! SafeRunnerModel with the main view. Constructing the model runs
//! loadSettings(), which pulls in every field — including three 512-character
//! free-text fields (medications, allergies, conditions) — and glance views
//! run under a much tighter memory budget than the full widget view, so
//! loading all of that just to read a blood type risked blowing it.
(:glance)
class SafeRunnerGlanceView extends WatchUi.GlanceView {
    private const BLOOD_TYPES = ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];

    function initialize() {
        GlanceView.initialize();
    }

    //! Blood type label, or null when unset/out of range. Mirrors the
    //! validation SafeRunnerModel does, on this one field only.
    private function readBloodType() as String? {
        var raw = null;
        try { raw = Application.Properties.getValue("bloodType"); } catch (ex) { return null; }
        var index = -1;
        if (raw instanceof Number) { index = raw as Number; }
        else if (raw instanceof String) {
            var parsed = (raw as String).toNumber();
            if (parsed != null) { index = parsed; }
        }
        if (index <= 0 || index >= BLOOD_TYPES.size()) { return null; }
        return BLOOD_TYPES[index] as String;
    }

    function onUpdate(dc as Dc) as Void {
        var text = "ICE";
        var bloodType = readBloodType();
        if (bloodType != null) {
            text += "  " + (bloodType as String);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, dc.getHeight() / 2, Graphics.FONT_TINY, text,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
