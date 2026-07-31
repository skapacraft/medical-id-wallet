// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Barcode renderer: QR (spec-compliant encoder, versions 1-4, ECC L) and
// Code 39 (A-Z 0-9 and basic symbols, sufficient for all national IDs).
// Code128 and PDF417 were dropped — see drawBarcodeAt() for why.
class BarcodeRenderer {
    private const CODE39_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. *$/+%";

    // Standard Code 39 table: 9 elements per character (5 bars + 4 spaces,
    // bar first, alternating). '1' = wide (3 units), '0' = narrow (1 unit).
    private const CODE39_PATTERNS = [
        "000110100",  // 0
        "100100001",  // 1
        "001100001",  // 2
        "101100000",  // 3
        "000110001",  // 4
        "100110000",  // 5
        "001110000",  // 6
        "000100101",  // 7
        "100100100",  // 8
        "001100100",  // 9
        "100001001",  // A
        "001001001",  // B
        "101001000",  // C
        "000011001",  // D
        "100011000",  // E
        "001011000",  // F
        "000001101",  // G
        "100001100",  // H
        "001001100",  // I
        "000011100",  // J
        "100000011",  // K
        "001000011",  // L
        "101000010",  // M
        "000010011",  // N
        "100010010",  // O
        "001010010",  // P
        "000000111",  // Q
        "100000110",  // R
        "001000110",  // S
        "000010110",  // T
        "110000001",  // U
        "011000001",  // V
        "111000000",  // W
        "010010001",  // X
        "110010000",  // Y
        "011010000",  // Z
        "010000101",  // -
        "110000100",  // .
        "011000100",  // space
        "010010100",  // *
        "010101000",  // $
        "010100010",  // /
        "010001010",  // +
        "000101010"   // %
    ];

    // Must stay an integer: element widths are accumulated into the bar X
    // position, and a fractional ratio (2.5 was tried) makes each "wide"
    // element land on a .5 boundary that fillRectangle truncates
    // inconsistently — the same wide bar renders 2px here and 3px there,
    // destroying the wide:narrow ratio a Code 39 scanner decodes on.
    // CHAR_UNITS below is derived from this value and must match it.
    private const WIDE_RATIO  = 3;   // wide element = 3 narrow units (spec: 2..3)
    private const QUIET_UNITS = 10;  // quiet zone on each side, in narrow units
    // Each char: 6 narrow + 3 wide = 6 + (3 * WIDE_RATIO) = 15 units,
    // + 1 inter-char gap = 16
    private const CHAR_UNITS  = 16;

    // A narrow bar this many pixels wide or less cannot be resolved by a real
    // scanner (laser/camera minimum X-dimension is ~0.19mm; on a 1.3" watch
    // face 1px is roughly 0.06mm). Below this we show the value as readable
    // text instead of a barcode nobody can actually scan.
    private const MIN_SCANNABLE_UNIT = 2;

    // Hint shown under the value on a fallback panel, explaining why bars/
    // modules were replaced by text. Swapping them silently reads as a broken
    // app rather than a deliberate decision.
    private const HINT_NONE        = 0;  // nothing useful to suggest
    private const HINT_USE_QR      = 1;  // Code 39 cannot fit this value
    private const HINT_QR_TOO_LONG = 2;  // value exceeds QR version 4 capacity

    // Horizontal inset on round displays so bars and white panel stay inside
    // the circular mask. On rectangular displays this is just padding.
    // Do not shrink this to gain barcode width: on a round display the panel
    // would be clipped by the bezel mask, and the extra pixels are far too
    // few to change whether a barcode fits (see MIN_SCANNABLE_UNIT).
    private const SIDE_MARGIN = 16;

    // QR matrix generation (RS error correction, module placement)
    // is expensive and was being redone from scratch on every single
    // onUpdate() — every scroll keypress, every redraw — with no caching.
    // For a larger QR (e.g. a 58-char payload needing version 3, vs. a
    // truncated 32-char one needing version 2) this could run long enough
    // to blow the render/watchdog budget on a MIP device (reported as the
    // app "freezing"). Cache the built matrix per (docType, text) and only
    // rebuild when the content actually changes.
    private var cachedKey    as String?;
    private var cachedResult as Dictionary?;

    // Whether the last drawBarcodeAt() call actually had the panel on screen.
    // The view uses this to decide about the backlight, instead of trying to
    // re-derive the panel height itself (its estimate did not match what QR
    // actually produces, so the backlight could trigger early or late).
    private var lastBarcodeVisible as Boolean = false;

    function initialize() {}

    function isLastBarcodeVisible() as Boolean { return lastBarcodeVisible; }

    //! True when a panel of panelH starting at topY intersects the viewport.
    //! Everything below is drawn inside a scrolling column, so most of the
    //! time the barcode sits far outside the screen; skipping the draw there
    //! avoids up to ~1100 fillRectangle() calls per frame for a version-4 QR
    //! (the matrix is cached, but the drawing loop was not being skipped).
    private function checkVisible(topY as Number, panelH as Number,
                                   screenH as Number) as Boolean {
        var visible = (topY < screenH) && ((topY + panelH) > 0);
        if (visible) { lastBarcodeVisible = true; }
        return visible;
    }

    //! Dispatch barcode rendering based on format type.
    //! 0 = None, 1 = QR, 2 = Code 39 (generic)
    //! Code128 and PDF417 were dropped: real-world usefulness for a
    //! responder without a proper scanner is low (see CHANGELOG), and
    //! neither followed the actual standard needed to interoperate with
    //! real hospital/DMV scanning systems anyway. QR (any phone camera) and
    //! Code39 (simple, reliable) cover the practical cases.
    //! Always returns the bottom Y of the section (including bottom padding)
    //! whether or not it was actually drawn, so scroll extents stay correct.
    function drawBarcodeAt(dc as Dc, docType as Number, text as String,
                            topY as Number, screenH as Number) as Number {
        lastBarcodeVisible = false;
        switch (docType) {
            case 1: return drawQrAt(dc, text, topY, screenH);
            case 2: return drawCode39At(dc, text, topY, screenH);
            default: return topY;
        }
    }

    //! Calculate safe square size for QR on round displays.
    //! Returns dimension that fits inside circular mask without clipping.
    private function safeSquareSize(dc as Dc) as Number {
        var settings = System.getDeviceSettings();
        var shape = settings.screenShape;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var base = w < h ? w : h;
        if (shape == System.SCREEN_SHAPE_ROUND) {
            return (base * 0.70).toNumber();
        }
        return (base * 0.85).toNumber();
    }

    //! QR code renderer (medical insurance / digital health).
    //! Full spec-compliant QR encoder: alphanumeric/byte mode, versions 1-4,
    //! ECC level L, Reed-Solomon (GF(256)) error correction, mask 0, real
    //! finder/timing/alignment/format-info placement. Scannable output.
    private function drawQrAt(dc as Dc, text as String, topY as Number,
                               screenH as Number) as Number {
        // Fallback panels show the plain value: the "[QR] " prefix that used
        // to be prepended here was internal notation leaking into an
        // emergency screen, where every character on display should be
        // information a responder can act on.
        if (!hasSufficientMemoryFor2DMatrix()) {
            return drawTextFallbackAt(dc, text, topY, screenH, HINT_NONE);
        }
        var key = "qr:" + text;
        var qr;
        if (cachedKey != null && (cachedKey as String).equals(key)) {
            qr = cachedResult;
        } else {
            qr = buildQrMatrix(text);
            cachedKey = key;
            cachedResult = qr;
        }
        if (qr == null) {
            return drawTextFallbackAt(dc, text, topY, screenH, HINT_QR_TOO_LONG);
        }
        var n = qr["size"] as Number;
        return renderModuleMatrix(dc, qr["modules"] as Array<Array<Boolean> >,
                                   n, n, topY, screenH);
    }

    //! Memory gate: full 2D matrix generation (RS tables, module grids) needs
    //! headroom that legacy MIP devices (e.g. Forerunner 255) don't have.
    //! AMOLED devices and newer MIP devices report larger totalMemory.
    private function hasSufficientMemoryFor2DMatrix() as Boolean {
        var stats = System.getSystemStats();
        return stats.totalMemory >= 100000;
    }

    //! Modules of quiet zone (blank border) on each side. The QR spec
    //! requires a minimum 4-module quiet zone for reliable finder-pattern
    //! detection by scanners — a fixed pixel margin (regardless of module
    //! size) was previously used instead, which was both too small for
    //! larger modules (scan failures) and added ON TOP of the pre-computed
    //! "safe" circular-display footprint (visual overflow past the safe
    //! area on round screens).
    private const QUIET_ZONE_MODULES = 4;

    //! Renders a boolean module grid (QR) as a white panel with black modules.
    private function renderModuleMatrix(dc as Dc, modules as Array<Array<Boolean> >, rows as Number,
                                         cols as Number, topY as Number,
                                         screenH as Number) as Number {
        var fullWidth  = dc.getWidth();
        var widthBudget = safeSquareSize(dc);
        var longestSide = rows > cols ? rows : cols;
        // Reserve the quiet zone's module-equivalent width WITHIN the safe
        // footprint budget, instead of adding it on top afterward.
        var moduleSize = widthBudget / (longestSide + (QUIET_ZONE_MODULES * 2));
        if (moduleSize < 1) { moduleSize = 1; }

        var gridW  = cols * moduleSize;
        var gridH  = rows * moduleSize;
        var quiet  = QUIET_ZONE_MODULES * moduleSize;
        var panelW = gridW + (2 * quiet);
        var panelH = gridH + (2 * quiet);
        var panelX = (fullWidth - panelW) / 2;

        if (!checkVisible(topY, panelH, screenH)) {
            return topY + panelH + 60;
        }

        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(panelX, topY, panelW, panelH);

        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        for (var r = 0; r < rows; r++) {
            var rowArr = modules[r] as Array<Boolean>;
            for (var c = 0; c < cols; c++) {
                if (rowArr[c]) {
                    dc.fillRectangle(panelX + quiet + (c * moduleSize),
                                      topY + quiet + (r * moduleSize),
                                      moduleSize, moduleSize);
                }
            }
        }
        return topY + panelH + 60;
    }

    // ---------------------------------------------------------------
    // QR encoder (versions 1-4, ECC level L)
    // ---------------------------------------------------------------

    private const QR_ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

    private function appendBits(bits as Array, value as Number, length as Number) as Void {
        for (var i = length - 1; i >= 0; i--) {
            bits.add((value >> i) & 1);
        }
    }

    private function isAlphanumericQr(text as String) as Boolean {
        for (var i = 0; i < text.length(); i++) {
            if (QR_ALPHANUMERIC.find(text.substring(i, i + 1)) == null) {
                return false;
            }
        }
        return true;
    }

    private function buildGf256Tables() as Dictionary {
        var expTable = new [512];
        var logTable = new [256];
        var val = 1;
        for (var i = 0; i < 255; i++) {
            expTable[i] = val;
            logTable[val] = i;
            val = val * 2;
            if (val >= 256) { val = val ^ 0x11D; }
        }
        for (var i = 255; i < 512; i++) { expTable[i] = expTable[i - 255]; }
        return { "exp" => expTable, "log" => logTable };
    }

    private function rsGeneratorPoly(ecCount as Number, gf as Dictionary) as Array {
        var exp = gf["exp"] as Array;
        var log = gf["log"] as Array;
        var poly = [1];
        for (var i = 0; i < ecCount; i++) {
            var newPoly = new [poly.size() + 1];
            for (var j = 0; j < newPoly.size(); j++) { newPoly[j] = 0; }
            for (var j = 0; j < poly.size(); j++) {
                newPoly[j] = newPoly[j] ^ poly[j];
                var product = (poly[j] == 0) ? 0 : exp[(log[poly[j]] + i) % 255];
                newPoly[j + 1] = newPoly[j + 1] ^ product;
            }
            poly = newPoly;
        }
        return poly;
    }

    private function rsComputeRemainder(data as Array, ecCount as Number, gf as Dictionary) as Array {
        var exp = gf["exp"] as Array;
        var log = gf["log"] as Array;
        var generator = rsGeneratorPoly(ecCount, gf);
        var remainder = new [ecCount];
        for (var i = 0; i < ecCount; i++) { remainder[i] = 0; }
        for (var i = 0; i < data.size(); i++) {
            var factor = data[i] ^ remainder[0];
            for (var j = 0; j < ecCount - 1; j++) { remainder[j] = remainder[j + 1]; }
            remainder[ecCount - 1] = 0;
            if (factor != 0) {
                var logFactor = log[factor];
                for (var j = 0; j < ecCount; j++) {
                    if (generator[j + 1] != 0) {
                        remainder[j] = remainder[j] ^ exp[(log[generator[j + 1]] + logFactor) % 255];
                    }
                }
            }
        }
        return remainder;
    }

    //! Reserves the finder pattern (7x7) plus its 1-module white separator
    //! on ALL sides facing the data area. BUG FIX: rowEnd/colEnd previously
    //! used `+7` (only covering the 7x7 finder itself), while rowStart/
    //! colStart used `-1` (correctly extending into the separator on the
    //! outward side). This meant the separator strip on the INWARD-facing
    //! side (e.g. the row below a top-aligned finder, or the column right
    //! of a left-aligned finder) was never reserved — data got placed and
    //! masked there instead of being kept a clean white separator, which is
    //! exactly what a real ISO/IEC 18004 decoder expects at fixed positions
    //! to detect and align each finder pattern. This silently produced a
    //! structurally QR-looking image with correct-looking finder squares
    //! (confirmed by OpenCV/zbar finding them) that nonetheless failed to
    //! decode — verified via an independent Python re-implementation cross-
    //! checked against the `qrcode` reference library's module matrix and
    //! zbar decoding.
    private function markFinderArea(modules as Array<Array<Boolean> >, isFn as Array<Array<Boolean> >, n as Number,
                                     top as Number, left as Number) as Void {
        var rowStart = top - 1; if (rowStart < 0) { rowStart = 0; }
        var rowEnd   = top + 8; if (rowEnd > n) { rowEnd = n; }
        var colStart = left - 1; if (colStart < 0) { colStart = 0; }
        var colEnd   = left + 8; if (colEnd > n) { colEnd = n; }
        for (var r = rowStart; r < rowEnd; r++) {
            for (var c = colStart; c < colEnd; c++) {
                isFn[r][c] = true;
                modules[r][c] = false;
            }
        }
        for (var dr = 0; dr < 7; dr++) {
            for (var dc = 0; dc < 7; dc++) {
                var black = (dr == 0 || dr == 6 || dc == 0 || dc == 6 ||
                             (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
                modules[top + dr][left + dc] = black;
            }
        }
    }

    private function drawTimingPatterns(modules as Array<Array<Boolean> >, isFn as Array<Array<Boolean> >, n as Number) as Void {
        for (var i = 8; i < n - 8; i++) {
            var black = ((i % 2) == 0);
            modules[6][i] = black; isFn[6][i] = true;
            modules[i][6] = black; isFn[i][6] = true;
        }
    }

    //! BUG FIX: must reserve exactly the cells setFormatBits() writes to
    //! (see that function for the corrected placement). The previous
    //! version under-reserved one column (row 8, col n-8), letting
    //! placeQrData() consume a real data bit into a cell that setFormatBits
    //! unconditionally overwrites afterward — silently dropping one bit and
    //! shifting every subsequent bit in the zig-zag traversal by one
    //! position, corrupting the entire rest of the payload.
    private function reserveFormatAreas(isFn as Array<Array<Boolean> >, n as Number) as Void {
        // Column 8 (vertical copy) — rows 0-5, 7, 8, then n-7..n-1, plus the
        // fixed dark module at row n-8.
        for (var i = 0; i <= 5; i++) { isFn[i][8] = true; }
        isFn[7][8] = true;
        isFn[8][8] = true;
        for (var i = n - 7; i <= n - 1; i++) { isFn[i][8] = true; }
        isFn[n - 8][8] = true;

        // Row 8 (horizontal copy) — cols 0-5, 7, then n-8..n-1.
        for (var i = 0; i <= 5; i++) { isFn[8][i] = true; }
        isFn[8][7] = true;
        for (var i = n - 8; i <= n - 1; i++) { isFn[8][i] = true; }
    }

    private function drawAlignmentPattern(modules as Array<Array<Boolean> >, isFn as Array<Array<Boolean> >, center as Number) as Void {
        for (var dr = -2; dr <= 2; dr++) {
            for (var dc = -2; dc <= 2; dc++) {
                var r = center + dr;
                var c = center + dc;
                var black = (dr == -2 || dr == 2 || dc == -2 || dc == 2 || (dr == 0 && dc == 0));
                modules[r][c] = black;
                isFn[r][c] = true;
            }
        }
    }

    //! Zig-zag data placement (Nayuki-style: two-column strips, skipping the
    //! vertical timing column, alternating scan direction each strip).
    private function placeQrData(modules as Array<Array<Boolean> >, isFn as Array<Array<Boolean> >, n as Number, codewords as Array) as Void {
        var bitLen = codewords.size() * 8;
        var bitIndex = 0;
        var col = n - 1;
        while (col >= 1) {
            if (col == 6) { col = 5; }
            for (var vert = 0; vert < n; vert++) {
                for (var j = 0; j < 2; j++) {
                    var c = col - j;
                    var upward = (((col + 1) & 2) == 0);
                    var row = upward ? (n - 1 - vert) : vert;
                    if (!isFn[row][c]) {
                        var bit = 0;
                        if (bitIndex < bitLen) {
                            var byteIdx = bitIndex / 8;
                            var bitOffset = 7 - (bitIndex % 8);
                            bit = (codewords[byteIdx] >> bitOffset) & 1;
                            bitIndex++;
                        }
                        modules[row][c] = (bit == 1);
                    }
                }
            }
            col -= 2;
        }
    }

    private function applyMask0(modules as Array<Array<Boolean> >, isFn as Array<Array<Boolean> >, n as Number) as Void {
        for (var r = 0; r < n; r++) {
            for (var c = 0; c < n; c++) {
                if (!isFn[r][c] && (((r + c) % 2) == 0)) {
                    modules[r][c] = !modules[r][c];
                }
            }
        }
    }

    //! BCH(15,5) format info for ECC level L + mask 0, XORed with the fixed
    //! format mask 0x5412 per the QR spec.
    private function computeFormatBits() as Number {
        var data = 0x08; // ECC L = 01, mask = 000
        var reg = data << 10;
        var poly = 0x537; // degree-10 generator, 11 bits
        for (var i = 14; i >= 10; i--) {
            if (((reg >> i) & 1) == 1) {
                reg = reg ^ (poly << (i - 10));
            }
        }
        return ((data << 10) | reg) ^ 0x5412;
    }

    //! BUG FIX: this function previously had row/column swapped for EVERY
    //! format-info bit (verified against the actual working placement logic
    //! of a real, zbar-decodable QR encoder — our computeFormatBits() value
    //! was independently confirmed byte-for-byte correct, but every bit was
    //! being written to modules[8][col] where it needed modules[row][8], and
    //! vice versa). This alone was enough to make every QR we generated
    //! fail to decode on a real scanner while still "looking like" a QR
    //! (finder patterns are unaffected by this bug), which matched exactly
    //! what was reported. Verified independently via a Python
    //! reimplementation, cross-checked module-by-module against a
    //! zbar-decodable reference QR image, until the diff was zero.
    private function setFormatBits(modules as Array<Array<Boolean> >, n as Number, format as Number) as Void {
        // "Vertical" copy — column 8, split top (bits 0-7) / bottom (bits 8-14)
        for (var i = 0; i <= 14; i++) {
            var bit = (((format >> i) & 1) == 1);
            if (i < 6) { modules[i][8] = bit; }
            else if (i < 8) { modules[i + 1][8] = bit; }
            else { modules[n - 15 + i][8] = bit; }
        }
        // "Horizontal" copy — row 8, split right (bits 0-7) / left (bits 8-14)
        for (var i = 0; i <= 14; i++) {
            var bit = (((format >> i) & 1) == 1);
            if (i < 8) { modules[8][n - i - 1] = bit; }
            else if (i < 9) { modules[8][15 - i] = bit; }
            else { modules[8][14 - i] = bit; }
        }
        modules[n - 8][8] = true; // dark module, always black
    }

    private function buildQrMatrix(text as String) as Dictionary? {
        var sizes             = [21, 25, 29, 33];
        var dataCodewordsCap  = [19, 34, 55, 80];
        var ecCounts          = [7, 10, 15, 20];
        var alignmentCenters  = [0, 18, 22, 26];

        // Bail out BEFORE doing any encoding work if the text is already too
        // long for version 4 in any mode (byte mode's ceiling is ~78 chars,
        // alphanumeric's is ~114) — previously the full bitstream was built
        // first and only checked against capacity afterward, so an
        // unbounded-length input (e.g. a long Barcode Override) could do a
        // lot of avoidable work, or worse, before falling back to text.
        if (text.length() > 120) { return null; }

        var alphanumeric = isAlphanumericQr(text);
        var bits = [];
        if (alphanumeric) {
            appendBits(bits, 0x2, 4);
            appendBits(bits, text.length(), 9);
            var i = 0;
            while (i < text.length()) {
                if (i + 1 < text.length()) {
                    var a = QR_ALPHANUMERIC.find(text.substring(i, i + 1));
                    var b = QR_ALPHANUMERIC.find(text.substring(i + 1, i + 2));
                    appendBits(bits, (a * 45) + b, 11);
                    i += 2;
                } else {
                    var a = QR_ALPHANUMERIC.find(text.substring(i, i + 1));
                    appendBits(bits, a, 6);
                    i += 1;
                }
            }
        } else {
            var byteData = text.toUtf8Array();
            appendBits(bits, 0x4, 4);
            appendBits(bits, byteData.size(), 8);
            for (var i = 0; i < byteData.size(); i++) { appendBits(bits, byteData[i], 8); }
        }

        var versionIdx = -1;
        for (var v = 0; v < sizes.size(); v++) {
            if ((dataCodewordsCap[v] * 8) >= bits.size()) { versionIdx = v; break; }
        }
        if (versionIdx == -1) { return null; } // text too long for v1-4/ECC L — fall back

        var capacityCodewords = dataCodewordsCap[versionIdx];
        var ecCount = ecCounts[versionIdx];
        var n = sizes[versionIdx];
        var capBits = capacityCodewords * 8;

        var termLen = capBits - bits.size();
        if (termLen > 4) { termLen = 4; }
        appendBits(bits, 0, termLen);
        while ((bits.size() % 8) != 0) { bits.add(0); }
        var padToggle = true;
        while (bits.size() < capBits) {
            appendBits(bits, padToggle ? 0xEC : 0x11, 8);
            padToggle = !padToggle;
        }

        var dataCodewords = new [capacityCodewords];
        for (var c = 0; c < capacityCodewords; c++) {
            var value = 0;
            for (var b = 0; b < 8; b++) { value = (value << 1) | bits[(c * 8) + b]; }
            dataCodewords[c] = value;
        }

        var gf = buildGf256Tables();
        var ecCodewords = rsComputeRemainder(dataCodewords, ecCount, gf);

        var allCodewords = new [capacityCodewords + ecCount];
        for (var i = 0; i < capacityCodewords; i++) { allCodewords[i] = dataCodewords[i]; }
        for (var i = 0; i < ecCount; i++) { allCodewords[capacityCodewords + i] = ecCodewords[i]; }

        var modules = new Array<Array<Boolean> >[n];
        var isFn = new Array<Array<Boolean> >[n];
        for (var r = 0; r < n; r++) {
            modules[r] = new Array<Boolean>[n];
            isFn[r] = new Array<Boolean>[n];
            for (var c = 0; c < n; c++) { modules[r][c] = false; isFn[r][c] = false; }
        }

        markFinderArea(modules, isFn, n, 0, 0);
        markFinderArea(modules, isFn, n, n - 7, 0);
        markFinderArea(modules, isFn, n, 0, n - 7);
        drawTimingPatterns(modules, isFn, n);
        reserveFormatAreas(isFn, n);
        if (versionIdx >= 1) {
            drawAlignmentPattern(modules, isFn, alignmentCenters[versionIdx]);
        }

        placeQrData(modules, isFn, n, allCodewords);
        applyMask0(modules, isFn, n);
        setFormatBits(modules, n, computeFormatBits());

        return { "size" => n, "modules" => modules };
    }


    //! Draw Code 39 at a specific Y coordinate (inline scrollable layout).
    //! Returns the bottom Y of the drawn section (including bottom padding).
    function drawCode39At(dc as Dc, text as String, topY as Number,
                           screenH as Number) as Number {
        var textH = dc.getFontHeight(Graphics.FONT_XTINY);
        var data  = filterCode39(text);
        if (data.length() == 0) {
            return drawTextFallbackAt(dc, text, topY, screenH, HINT_USE_QR);
        }
        var payload = "*" + data + "*";

        // Use inner width minus side margins to stay inside the circular mask.
        var fullWidth  = dc.getWidth();
        var innerWidth = fullWidth - (2 * SIDE_MARGIN);
        var barH       = dc.getHeight() / 2;

        var totalUnits = (payload.length() * CHAR_UNITS) - 1 + (2 * QUIET_UNITS);
        var unit = innerWidth / totalUnits;
        // Integer division: unit is the narrow-bar width in whole pixels.
        // Anything under MIN_SCANNABLE_UNIT would draw a barcode that looks
        // plausible but that no scanner can decode (previously unit == 1 was
        // allowed, i.e. hairline bars); show the readable value instead of a
        // barcode that only pretends to work.
        if (unit < MIN_SCANNABLE_UNIT) {
            // Explain the substitution instead of silently swapping bars for
            // text: the user picked a barcode format and got plain text, which
            // reads as a broken app rather than a deliberate decision.
            return drawTextFallbackAt(dc, data, topY, screenH, HINT_USE_QR);
        }

        var panelH = barH + textH + 20;
        if (!checkVisible(topY, panelH, screenH)) {
            return topY + panelH + 60;
        }

        // White panel centred horizontally with side margins
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(SIDE_MARGIN, topY, innerWidth, panelH);

        // Draw bars
        var barcodeWidth = totalUnits * unit;
        var x    = SIDE_MARGIN + ((innerWidth - barcodeWidth) / 2) + (QUIET_UNITS * unit);
        var barY = topY + 6;

        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        for (var c = 0; c < payload.length(); c++) {
            var ch = payload.substring(c, c + 1) as String;
            var charIndex = CODE39_CHARS.find(ch);
            if (charIndex == null) { continue; }
            var pattern = CODE39_PATTERNS[charIndex] as String;
            for (var i = 0; i < 9; i++) {
                var isWide       = pattern.substring(i, i + 1).equals("1");
                var elementWidth = (isWide ? WIDE_RATIO : 1) * unit;
                if ((i % 2) == 0) {
                    dc.fillRectangle(x, barY, elementWidth, barH - 10);
                }
                x += elementWidth;
            }
            x += unit;  // inter-character gap
        }

        // Human-readable value under the bars (standard barcode practice)
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(fullWidth / 2, barY + barH - 6, Graphics.FONT_XTINY, data,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Extra bottom margin so the user can scroll until the barcode is centred
        return topY + panelH + 60;
    }

    //! Keep only Code 39-encodable characters ('*' is framing-only, excluded).
    private function filterCode39(text as String) as String {
        var upper  = text.toUpper();
        var result = "";
        for (var i = 0; i < upper.length(); i++) {
            var ch = upper.substring(i, i + 1) as String;
            if (!ch.equals("*") && CODE39_CHARS.find(ch) != null) {
                result += ch;
            }
        }
        return result;
    }

    //! White panel with large text — used when bars would be sub-pixel wide.
    //! hint: one of HINT_*. "Switch to QR" is only meaningful on the Code 39
    //! paths — when QR itself is what failed, the user is already using it, so
    //! that path gets its own message (or none, when there is nothing
    //! actionable to say).
    private function drawTextFallbackAt(dc as Dc, text as String,
                                        topY as Number, screenH as Number,
                                        hint as Number) as Number {
        var fullWidth  = dc.getWidth();
        var innerWidth = fullWidth - (2 * SIDE_MARGIN);
        var panelH     = dc.getHeight() / 2;
        if (!checkVisible(topY, panelH, screenH)) {
            return topY + panelH + 60;
        }
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(SIDE_MARGIN, topY, innerWidth, panelH);

        // Step down through the font sizes until the value fits inside the
        // panel. It was always drawn at FONT_SMALL, so a full-length national
        // ID ran edge to edge and past the panel — and this path now handles
        // every barcode that is too dense to be scannable, so it has to stay
        // readable for the longest ID the settings allow (32 characters).
        var font    = Graphics.FONT_SMALL;
        var textPad = 12;
        var fonts   = [Graphics.FONT_SMALL, Graphics.FONT_XTINY] as Array<FontType>;
        for (var i = 0; i < fonts.size(); i++) {
            font = fonts[i] as FontType;
            if (dc.getTextWidthInPixels(text, font) <= innerWidth - textPad) { break; }
        }

        var showHint = (hint != HINT_NONE);
        var fontH = dc.getFontHeight(font);
        var hintH = showHint ? dc.getFontHeight(Graphics.FONT_XTINY) : 0;
        // Centre the value and hint together as one block, so the value does
        // not sit visually off-centre once the hint is added below it.
        var blockY = topY + (panelH - (fontH + hintH)) / 2;

        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.drawText(fullWidth / 2, blockY, font, text, Graphics.TEXT_JUSTIFY_CENTER);

        if (showHint) {
            var hintText = (hint == HINT_QR_TOO_LONG)
                ? WatchUi.loadResource(Rez.Strings.barcodeTooLongQr) as String
                : WatchUi.loadResource(Rez.Strings.barcodeTooLong) as String;
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(fullWidth / 2, blockY + fontH, Graphics.FONT_XTINY,
                        hintText, Graphics.TEXT_JUSTIFY_CENTER);
        }
        return topY + panelH + 60;
    }
}
