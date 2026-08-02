// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Attention;
import Toybox.System;

class SafeRunnerView extends WatchUi.View {
    private var model           as SafeRunnerModel;
    private var barcodeRenderer as BarcodeRenderer;

    private const COLOR_BLACK    = 0x000000;
    private const COLOR_WHITE    = 0xFFFFFF;
    private const COLOR_RED_NEON = 0xFF0000;
    private const COLOR_GREY     = 0xAAAAAA;

    //! Set on the base view of a widget whose up/down buttons belong to the
    //! carousel: without a cue, that screen looks like the whole app and the
    //! rest of the profile is unreachable. "START" is the physical button
    //! label on Garmin wearables, so it needs no translation.
    private var showOpenHint as Boolean;

    function initialize(model as SafeRunnerModel, showOpenHint as Boolean) {
        View.initialize();
        self.model = model;
        self.showOpenHint = showOpenHint;
        barcodeRenderer = new BarcodeRenderer();
    }

    function onLayout(dc as Dc) as Void {}

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_WHITE, COLOR_BLACK);
        dc.clear();
        var backlightOn = false;
        try {
            backlightOn = drawMainScreen(dc);
        } catch (ex) {
            // Render aborted partway through — avoid leaving a stuck black
            // frame; reset scroll so the next update starts from a known-good state.
            // Deliberately NO requestUpdate() here: if the failure is
            // deterministic (and it would be, since the barcode is part of
            // every frame) requesting another update from inside the failure
            // handler produces an unbounded onUpdate -> throw -> requestUpdate
            // loop that pins the CPU and leaves the widget stuck. The next
            // real user interaction redraws anyway.
            model.setScrollOffset(0);
            dc.setColor(COLOR_WHITE, COLOR_BLACK);
            dc.clear();
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL,
                "..", Graphics.TEXT_JUSTIFY_CENTER);
        }
        // Only ever request backlight ON when the barcode is visible.
        // Attention.backlight() "always respect[s] the backlight timeout
        // settings on the device" (per the SDK docs), so it turns itself
        // off naturally — an explicit backlight(false) call was causing a
        // black-frame glitch on some devices (e.g. Forerunner 170) both
        // when scrolling the barcode out of view and when closing the
        // widget via Back.
        if (backlightOn) {
            setBacklight(true);
        }
        if (showOpenHint && model.hasData()) {
            drawOpenHint(dc);
        }
    }

    //! Bottom-of-screen cue drawn over the content, telling the wearer the
    //! profile continues behind a button press. Drawn last so scrolled
    //! content cannot paint over it.
    private function drawOpenHint(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var hintH = dc.getFontHeight(Graphics.FONT_XTINY);
        // Band is taller than the label so a content line ending just above
        // it is covered outright rather than left half-drawn.
        var bandY = h - hintH - 12;
        dc.setColor(COLOR_BLACK, COLOR_BLACK);
        dc.fillRectangle(0, bandY, w, h - bandY);

        // "START" is printed on the hardware, so it stays untranslated; the
        // verb around it is localized. Longer languages (hu, fr) can outrun
        // a narrow round screen, so fall back to the bare button name rather
        // than let the cue run under the bezel.
        var label = WatchUi.loadResource(Rez.Strings.pressStart) as String;
        if (dc.getTextWidthInPixels(label, Graphics.FONT_XTINY) > w - 8) {
            label = "START";
        }
        dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, bandY + 4, Graphics.FONT_XTINY, label,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Single scrollable screen: ICE info followed by barcode inline.
    // Returns true when the barcode panel is in the viewport (activates backlight).
    private function drawMainScreen(dc as Dc) as Boolean {
        var width   = dc.getWidth();
        var height  = dc.getHeight();
        var centerX = width / 2;

        // Empty state: no data configured yet. Previously the two hint
        // lines were hardcoded English text, never localized — fixed here,
        // plus a third line suggesting the minimum recommended fields so a
        // first-time user isn't left guessing where to start.
        if (!model.hasData()) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 - 40, Graphics.FONT_SMALL,
                WatchUi.loadResource(Rez.Strings.noData) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 - 5, Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.openConnectMobile) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX, height / 2 + 12, Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.setupProfileHint) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(COLOR_RED_NEON, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, height / 2 + 34, Graphics.FONT_XTINY,
                WatchUi.loadResource(Rez.Strings.minimumFieldsHint) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            return false;
        }

        var scrollOffset = model.getScrollOffset();

        var topMargin = height > 400 ? 35 : 45;
        // Round displays lose usable width near the very top edge (chord
        // width shrinks toward the bezel curve); push content down a bit
        // further so the first label isn't clipped by the circular mask.
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            topMargin += 15;
        }
        var yPos = topMargin - scrollOffset;
        var tiny  = Graphics.FONT_XTINY;
        var small = Graphics.FONT_SMALL;
        var tinyH = dc.getFontHeight(tiny);

        // First name / last name — on separate lines, since long full names
        // (e.g. double surnames) can overflow the screen width on one line
        var firstName = model.getFirstName();
        var lastName  = model.getLastName();
        if (firstName != null || lastName != null) {
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var smallH = dc.getFontHeight(small);
            if (firstName != null) {
                dc.drawText(centerX, yPos, small, firstName as String, Graphics.TEXT_JUSTIFY_CENTER);
                yPos += smallH;
            }
            if (lastName != null) {
                dc.drawText(centerX, yPos, small, lastName as String, Graphics.TEXT_JUSTIFY_CENTER);
                yPos += smallH;
            }
            yPos += 10;
        }

        // Blood type — critical for transfusion decisions, kept visually
        // prominent (red box)
        var bloodType = model.getBloodType();
        if (bloodType != null) {
            var medH = dc.getFontHeight(Graphics.FONT_MEDIUM);
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.bloodTypeLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;

            var boxH = medH + 4;
            var boxW = width / 2;
            dc.setColor(COLOR_RED_NEON, COLOR_RED_NEON);
            dc.fillRoundedRectangle(centerX - (boxW / 2), yPos, boxW, boxH, 6);
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos + 2, Graphics.FONT_MEDIUM, bloodType,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += boxH + 12;
        }

        // Age — computed from DOB; responders need age faster than an exact
        // birth date for triage/dosing decisions
        var age = model.getAge();
        if (age != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.ageLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny, age as String, Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 10;
        }

        // National / Health ID — identity/insurance lookup
        var nationalId = model.getNationalId();
        if (nationalId != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.nationalIdLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny, nationalId, Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 10;
        }

        // Allergies — must be known before administering anything
        var allergies = model.getAllergies();
        if (allergies != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.allergiesLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            yPos += tinyH * drawWrappedText(dc, allergies, centerX, yPos,
                                             width * 3 / 4, tiny) + 10;
        }

        // Medications — interaction risk, needed right after allergies
        var medications = model.getMedications();
        if (medications != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.medicationsLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            yPos += tinyH * drawWrappedText(dc, medications, centerX, yPos,
                                             width * 3 / 4, tiny) + 10;
        }

        // Medical conditions — context for symptoms
        var cond = model.getConditions();
        if (cond != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.conditionsLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            yPos += tinyH * drawWrappedText(dc, cond, centerX, yPos,
                                             width * 3 / 4, tiny) + 10;
        }

        // Height · Weight — secondary, useful for dosing/imaging
        var physical = model.getPhysicalInfo();
        if (physical != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny, physical, Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 10;
        }

        // Emergency contacts — name + relationship shown with the number,
        // since a bare phone number is nearly useless to a responder who
        // doesn't know if it's a spouse, parent, or a random contact
        var c1Line = contactDisplayLine(model.getIceContact1Name(), model.getIceContact1Rel(), model.getIceContact1());
        var c2Line = contactDisplayLine(model.getIceContact2Name(), model.getIceContact2Rel(), model.getIceContact2());
        if (c1Line != null || c2Line != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.contactsLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (c1Line != null) {
                yPos += tinyH * drawWrappedText(dc, c1Line as String, centerX, yPos,
                                                 width * 3 / 4, tiny);
            }
            if (c2Line != null) {
                yPos += tinyH * drawWrappedText(dc, c2Line as String, centerX, yPos,
                                                 width * 3 / 4, tiny);
            }
            yPos += 10;
        }

        // Organ donor status — secondary
        var donor = model.getDonorStatus();
        if (donor != 0) {
            var donorText = donor == 1
                ? WatchUi.loadResource(Rez.Strings.donorYes) as String
                : WatchUi.loadResource(Rez.Strings.donorNo) as String;
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.donorStatusLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny, donorText, Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 10;
        }

        // Date of birth — exact date kept for reference, after the computed age
        var dob = model.getDateOfBirth();
        if (dob != null) {
            dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny,
                WatchUi.loadResource(Rez.Strings.dateOfBirthLabel) as String,
                Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 1;
            dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, yPos, tiny, dob as String, Graphics.TEXT_JUSTIFY_CENTER);
            yPos += tinyH + 10;
        }

        // Barcode inline — appended after all text fields. Dispatches on the
        // user's selected format (None/QR/Code39); both use the same simple
        // National ID / Barcode Override content.
        // The renderer decides visibility itself and skips the (expensive)
        // module/bar drawing when the panel is off screen, then reports back
        // whether it was on screen. The view used to estimate the panel
        // height here to make that call, but its estimate never matched what
        // the QR path actually produces, so the backlight could fire while
        // the code was still off screen (or not at all).
        var barcodeVisible = false;
        if (model.hasDocument()) {
            yPos += 12;
            var content = model.getBarcodeContent();
            if (content != null) {
                // Optional caption: without it the panel is a bare code, and
                // neither the wearer nor a responder can tell whether it is a
                // race bib, an insurance number or a health-profile link.
                var docLabel = model.getDocLabel();
                if (docLabel != null) {
                    dc.setColor(COLOR_GREY, Graphics.COLOR_TRANSPARENT);
                    yPos += tinyH * drawWrappedText(dc, docLabel as String, centerX,
                                                     yPos, width * 3 / 4, tiny) + 4;
                }
                yPos = barcodeRenderer.drawBarcodeAt(dc, model.getDocType(),
                                                      content as String, yPos, height);
                barcodeVisible = barcodeRenderer.isLastBarcodeVisible();
            }
        }

        // Update max scroll so DOWN key stops at the bottom
        model.setMaxScroll(yPos + scrollOffset - height + 10);

        return barcodeVisible;
    }

    //! "Jane Doe (Spouse) +1 555 0101" — a bare phone number tells a
    //! responder nothing about who to call or why; name + relationship do.
    private function contactDisplayLine(name as String?, relation as String?,
                                         phone as String?) as String? {
        var line = "";
        if (name != null) { line += name as String; }
        if (relation != null) {
            line += (line.length() > 0 ? " (" : "(") + (relation as String) + ")";
        }
        if (phone != null) { line += (line.length() > 0 ? " " : "") + (phone as String); }
        return line.length() > 0 ? line : null;
    }

    private function setBacklight(enabled as Boolean) as Void {
        if (Attention has :backlight) {
            try { Attention.backlight(enabled); } catch (ex) {}
        }
    }

    //! Splits text into the lines that will actually be rendered.
    //! Single source of truth for drawing and for height measurement: these
    //! were two separate implementations, and the measuring one hardcoded
    //! FONT_XTINY regardless of the font it was given — any divergence
    //! between them silently offset every field below it.
    //! A word wider than maxW is broken character-by-character rather than
    //! drawn past the screen edge: a long unbroken medication or allergen
    //! name used to have its tail clipped away with no indication.
    private function wrapLines(dc as Dc, text as String, maxW as Number,
                                font as FontType) as Array<String> {
        var lines = [] as Array<String>;
        var words = splitWords(text);
        var line  = "";
        for (var i = 0; i < words.size(); i++) {
            var w = words[i];
            while (dc.getTextWidthInPixels(w, font) > maxW && w.length() > 1) {
                var fit = 1;
                while (fit < w.length() && dc.getTextWidthInPixels(
                        w.substring(0, fit + 1) as String, font) <= maxW) {
                    fit++;
                }
                if (line.length() > 0) { lines.add(line); line = ""; }
                lines.add(w.substring(0, fit) as String);
                w = w.substring(fit, w.length()) as String;
            }
            var test = line.length() == 0 ? w : line + " " + w;
            if (dc.getTextWidthInPixels(test, font) > maxW && line.length() > 0) {
                lines.add(line);
                line = w;
            } else {
                line = test;
            }
        }
        if (line.length() > 0) { lines.add(line); }
        return lines;
    }

    private function splitWords(text as String) as Array<String> {
        var words     = [] as Array<String>;
        var remaining = text;
        while (remaining.length() > 0) {
            var idx = remaining.find(" ");
            if (idx == null) {
                words.add(remaining);
                remaining = "";
            } else {
                var w = remaining.substring(0, idx) as String;
                if (w.length() > 0) { words.add(w); }
                remaining = remaining.substring(idx + 1, remaining.length()) as String;
            }
        }
        return words;
    }

    //! Draws the text wrapped and returns how many lines it occupied, so the
    //! caller can advance yPos without wrapping the same text a second time.
    private function drawWrappedText(dc as Dc, text as String, cx as Number,
                                     y as Number, maxW as Number,
                                     font as FontType) as Number {
        var lines = wrapLines(dc, text, maxW, font);
        var lineH = dc.getFontHeight(font);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, font, lines[i] as String, Graphics.TEXT_JUSTIFY_CENTER);
            y += lineH;
        }
        return lines.size();
    }

    //! The base view and the pushed view share one model, so the scroll
    //! position the pushed view was left at would otherwise still be applied
    //! when the user backs out to the base view — which then shows the
    //! middle of the profile behind the "press START" cue instead of the
    //! summary it is meant to be.
    function onShow() as Void {
        if (showOpenHint) { model.setScrollOffset(0); }
    }
    // No explicit backlight(false) here — Attention.backlight() already
    // respects the device's own timeout, and forcing it off while the view
    // is closing was the source of a black-frame glitch on some devices.
    function onHide() as Void {}
}
