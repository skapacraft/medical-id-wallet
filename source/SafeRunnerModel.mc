// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SkapaCraft (skapacraft.com)
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. See LICENSE for details.

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Not (:glance): the glance view reads its single field directly, so this
//! model — which loads every field, including three 512-character ones —
//! stays out of the glance memory budget entirely.
class SafeRunnerModel {
    private const PROP_FIRST_NAME   = "firstName";
    private const PROP_LAST_NAME    = "lastName";
    private const PROP_BLOOD_TYPE   = "bloodType";
    private const PROP_ICE_CONTACT1     = "iceContact1";
    private const PROP_ICE_CONTACT1_NAME = "iceContact1Name";
    private const PROP_ICE_CONTACT1_REL  = "iceContact1Rel";
    private const PROP_ICE_CONTACT2     = "iceContact2";
    private const PROP_ICE_CONTACT2_NAME = "iceContact2Name";
    private const PROP_ICE_CONTACT2_REL  = "iceContact2Rel";
    private const PROP_UNIT_SYSTEM  = "unitSystem";
    private const PROP_HEIGHT       = "height";
    private const PROP_WEIGHT       = "weight";
    private const PROP_MEDICATIONS  = "medications";
    private const PROP_ALLERGIES    = "allergies";
    private const PROP_CONDITIONS   = "conditions";
    private const PROP_NATIONAL_ID  = "nationalId";
    private const PROP_DOC_STRING   = "docString";
    private const PROP_DOC_LABEL    = "docLabel";
    private const PROP_DATE_OF_BIRTH = "dateOfBirth";
    private const PROP_DONOR_STATUS  = "donorStatus";
    private const PROP_DOC_TYPE     = "docType";

    private var firstName   as String?;
    private var lastName    as String?;
    private var bloodType   as String?;
    private var iceContact1     as String?;
    private var iceContact1Name as String?;
    private var iceContact1Rel  as String?;
    private var iceContact2     as String?;
    private var iceContact2Name as String?;
    private var iceContact2Rel  as String?;
    private var unitSystem  as Number = 0; // 0 = Metric, 1 = Imperial
    private var height      as String?;
    private var weight      as String?;
    private var medications as String?;
    private var allergies   as String?;
    private var conditions  as String?;
    private var nationalId  as String?;
    private var docString   as String?;
    private var docLabel    as String?;
    private var dateOfBirth as String?;
    // 0 = not specified, 1 = Yes, 2 = No. Kept as the raw index rather than a
    // display string: the value shown on-watch has to come from the localized
    // resources (it used to be a hardcoded English "Yes"/"No", so an Italian
    // or Japanese watch still read "ORGAN DONOR: Yes" even though translations
    // for it already existed in all 20 languages).
    private var donorStatus as Number = 0;
    // 0=None, 1=QR, 2=Code39(generic)
    private var docType     as Number = 0;

    private var scrollOffset as Number = 0;
    private var maxScroll    as Number = 9999;

    function initialize() { loadSettings(); }

    function getScrollOffset() as Number { return scrollOffset; }
    function setScrollOffset(offset as Number) as Void { scrollOffset = offset; }
    function setMaxScroll(v as Number) as Void { maxScroll = v > 0 ? v : 0; }
    function scrollUp() as Void {
        var next = scrollOffset + 50;
        scrollOffset = next <= maxScroll ? next : maxScroll;
    }
    function scrollDown() as Void {
        var next = scrollOffset - 50;
        scrollOffset = next >= 0 ? next : 0;
    }

    function loadSettings() as Void {
        var BLOOD_TYPES = ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] as Array<String>;

        firstName   = sanitizeString(getProp(PROP_FIRST_NAME),   255);
        lastName    = sanitizeString(getProp(PROP_LAST_NAME),    255);
        bloodType   = listValue(getProp(PROP_BLOOD_TYPE), BLOOD_TYPES);
        unitSystem  = numberValue(getProp(PROP_UNIT_SYSTEM), 0);
        iceContact1     = sanitizeString(getProp(PROP_ICE_CONTACT1), 255);
        iceContact1Name = sanitizeString(getProp(PROP_ICE_CONTACT1_NAME), 60);
        iceContact1Rel  = sanitizeString(getProp(PROP_ICE_CONTACT1_REL), 30);
        iceContact2     = sanitizeString(getProp(PROP_ICE_CONTACT2), 255);
        iceContact2Name = sanitizeString(getProp(PROP_ICE_CONTACT2_NAME), 60);
        iceContact2Rel  = sanitizeString(getProp(PROP_ICE_CONTACT2_REL), 30);
        height      = formatMeasurement(sanitizeFloat(getProp(PROP_HEIGHT)));
        weight      = formatMeasurement(sanitizeFloat(getProp(PROP_WEIGHT)));
        medications = sanitizeString(getProp(PROP_MEDICATIONS),  512);
        allergies   = sanitizeString(getProp(PROP_ALLERGIES),    512);
        conditions  = sanitizeString(getProp(PROP_CONDITIONS),   512);
        dateOfBirth = sanitizeDateOfBirth(getProp(PROP_DATE_OF_BIRTH));
        donorStatus = numberValue(getProp(PROP_DONOR_STATUS), 0);
        if (donorStatus < 0 || donorStatus > 2) { donorStatus = 0; }
        docType     = numberValue(getProp(PROP_DOC_TYPE), 0);
        nationalId  = sanitizeString(getProp(PROP_NATIONAL_ID),  32);
        docString   = sanitizeString(getProp(PROP_DOC_STRING),   255);
        docLabel    = sanitizeString(getProp(PROP_DOC_LABEL),     30);

        purgeLegacyStorage();
    }

    private function getProp(key as String) as Object? {
        try { return Application.Properties.getValue(key); } catch (ex) { return null; }
    }

    //! Security fix: earlier versions mirrored every sensitive field (name,
    //! blood type, national ID, allergies, medications, contacts, DOB, donor
    //! status) into Application.Storage on every loadSettings() call, but
    //! that copy was never read back anywhere — Application.Properties was
    //! always the source of truth. This left an unnecessary, unread second
    //! persistent copy of medical/PII data on-device. This one-time purge
    //! removes any such copy left behind by a prior install; no new code
    //! path writes to Storage going forward.
    private function purgeLegacyStorage() as Void {
        var legacyKeys = [
            PROP_FIRST_NAME, PROP_LAST_NAME, PROP_BLOOD_TYPE, PROP_ICE_CONTACT1,
            PROP_ICE_CONTACT2, PROP_HEIGHT, PROP_WEIGHT, PROP_MEDICATIONS,
            PROP_ALLERGIES, PROP_CONDITIONS, PROP_DATE_OF_BIRTH, PROP_DONOR_STATUS,
            PROP_NATIONAL_ID, PROP_DOC_STRING
        ];
        for (var i = 0; i < legacyKeys.size(); i++) {
            try { Application.Storage.deleteValue(legacyKeys[i]); } catch (ex) {}
        }
    }

    private function numberValue(value as Object?, defaultValue as Number) as Number {
        if (value instanceof Number) { return value as Number; }
        if (value instanceof String) {
            var parsed = (value as String).toNumber();
            if (parsed != null) { return parsed; }
        }
        return defaultValue;
    }

    private function listValue(value as Object?, options as Array<String>) as String? {
        var index = -1;
        if (value instanceof Number) { index = value as Number; }
        else if (value instanceof String) {
            var parsed = (value as String).toNumber();
            if (parsed != null) { index = parsed; }
        }
        if (index < 0 || index >= options.size()) { return null; }
        var result = options[index] as String;
        return result.length() > 0 ? result : null;
    }

    private function sanitizeString(value as Object?, maxLength as Number) as String? {
        if (!(value instanceof String)) { return null; }
        var str = value as String;
        if (str.length() == 0) { return null; }
        if (str.length() > maxLength) { return str.substring(0, maxLength) as String; }
        return str;
    }

    //! Date of birth is free-typed text (no native date picker exists in
    //! the CIQ settings framework — confirmed unavailable earlier). A typo
    //! like "1990/05/14" or "14-05-1990" previously got stored and rendered
    //! as-is, while getAge() silently returned null for it — a user could
    //! easily not notice the age was missing and never realize why. Now a
    //! malformed date is rejected outright (treated as "not filled") rather
    //! than displayed as unreliable-looking text with a silently absent age.
    private function sanitizeDateOfBirth(value as Object?) as String? {
        var raw = sanitizeString(value, 10);
        if (raw == null) { return null; }
        if (raw.length() != 10) { return null; }
        if (!raw.substring(4, 5).equals("-") || !raw.substring(7, 8).equals("-")) { return null; }
        var year  = raw.substring(0, 4).toNumber();
        var month = raw.substring(5, 7).toNumber();
        var day   = raw.substring(8, 10).toNumber();
        if (year == null || month == null || day == null) { return null; }
        if (year < 1900 || year > 2100) { return null; }
        if (month < 1 || month > 12) { return null; }
        if (day < 1 || day > daysInMonth(year, month)) { return null; }
        return raw;
    }

    //! Real month length, so "1990-02-31" is rejected rather than accepted and
    //! then fed to getAge() as if it were a date.
    private function daysInMonth(year as Number, month as Number) as Number {
        if (month == 2) {
            var leap = ((year % 4) == 0 && (year % 100) != 0) || ((year % 400) == 0);
            return leap ? 29 : 28;
        }
        if (month == 4 || month == 6 || month == 9 || month == 11) { return 30; }
        return 31;
    }

    //! height/weight are "numeric" (float) settings — accepts Float, Number,
    //! or a numeric String (older cached values before the numeric picker).
    //! 0.0 is the property's required default and is treated as "not set"
    //! (no legitimate height/weight is zero).
    private function sanitizeFloat(value as Object?) as Float? {
        var v = null;
        if (value instanceof Float) { v = value as Float; }
        else if (value instanceof Number) { v = (value as Number).toFloat(); }
        else if (value instanceof String) { v = (value as String).toFloat(); }
        if (v == null || (v as Float) == 0.0) { return null; }
        return v as Float;
    }

    //! Whole numbers render without a decimal point (e.g. "170" not "170.0").
    private function formatMeasurement(value as Float?) as String? {
        if (value == null) { return null; }
        var v = value as Float;
        if (v == v.toNumber().toFloat()) { return v.toNumber().toString(); }
        return v.format("%.1f");
    }

    function getFirstName()   as String? { return firstName; }
    function getLastName()    as String? { return lastName; }
    function getBloodType()   as String? { return bloodType; }
    function getIceContact1() as String? { return iceContact1; }
    function getIceContact2() as String? { return iceContact2; }
    function getHeight()      as String? { return height; }
    function getWeight()      as String? { return weight; }
    function getMedications() as String? { return medications; }
    function getAllergies()    as String? { return allergies; }
    function getConditions()  as String? { return conditions; }
    function getDateOfBirth() as String? { return dateOfBirth; }

    //! Computed age in years from dateOfBirth (YYYY-MM-DD), for medical
    //! responders who need age at a glance more than the exact birth date.
    //! Returns null if dateOfBirth is unset or malformed.
    function getAge() as String? {
        if (dateOfBirth == null) { return null; }
        var dob = dateOfBirth as String;
        if (dob.length() != 10) { return null; }
        var year  = dob.substring(0, 4).toNumber();
        var month = dob.substring(5, 7).toNumber();
        var day   = dob.substring(8, 10).toNumber();
        if (year == null || month == null || day == null) { return null; }

        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var age = today.year - year;
        if (today.month < month || (today.month == month && today.day < day)) {
            age -= 1;
        }
        if (age < 0 || age > 130) { return null; }
        return age.toString();
    }
    //! 0 = not specified (nothing to show), 1 = Yes, 2 = No. The view maps
    //! this to the localized Rez string.
    function getDonorStatus() as Number { return donorStatus; }
    function getNationalId()  as String? { return nationalId; }
    function getIceContact1Name() as String? { return iceContact1Name; }
    function getIceContact1Rel()  as String? { return iceContact1Rel; }
    function getIceContact2Name() as String? { return iceContact2Name; }
    function getIceContact2Rel()  as String? { return iceContact2Rel; }

    //! Appends the unit chosen via the "unitSystem" setting (cm/kg for
    //! Metric, in/lb for Imperial) — the settings page runs on the phone and
    //! cannot read the watch's own unit setting at render time, so the user
    //! picks explicitly instead.
    private function heightWithUnit() as String? {
        if (height == null) { return null; }
        var unit = unitSystem == 1 ? "in" : "cm";
        return (height as String) + " " + unit;
    }

    private function weightWithUnit() as String? {
        if (weight == null) { return null; }
        var unit = unitSystem == 1 ? "lb" : "kg";
        return (weight as String) + " " + unit;
    }

    function getPhysicalInfo() as String? {
        var h = heightWithUnit();
        var w = weightWithUnit();
        if (h != null && w != null) { return h + " · " + w; }
        if (h != null) { return h; }
        if (w != null) { return w; }
        return null;
    }

    //! BUG FIX: docString ("Barcode override") was being used as a
    //! fallback ONLY when nationalId was empty — the opposite of what
    //! "override" means (it should replace the default when set). Now
    //! docString wins whenever it's non-empty, falling back to nationalId
    //! only when no override is configured.
    function getBarcodeContent() as String? {
        if (docString != null) { return docString; }
        return nationalId;
    }

    //! Optional caption for the barcode panel ("Race #", "MedicAlert", …).
    function getDocLabel() as String? { return docLabel; }

    //! Must cover EVERY field the view can render. It previously omitted
    //! medications, height, weight and docString, so a user who filled in
    //! only their medications (or only height/weight, or only the alternate
    //! barcode code) got the "no ICE data configured" screen and their data
    //! was never displayed at all — drawMainScreen() returns early on false.
    function hasData() as Boolean {
        if (firstName   != null) { return true; }
        if (lastName    != null) { return true; }
        if (bloodType   != null) { return true; }
        if (iceContact1 != null) { return true; }
        if (iceContact1Name != null) { return true; }
        if (iceContact1Rel  != null) { return true; }
        if (iceContact2 != null) { return true; }
        if (iceContact2Name != null) { return true; }
        if (iceContact2Rel  != null) { return true; }
        if (nationalId  != null) { return true; }
        if (allergies   != null) { return true; }
        if (medications != null) { return true; }
        if (conditions  != null) { return true; }
        if (height      != null) { return true; }
        if (weight      != null) { return true; }
        if (docString   != null) { return true; }
        if (dateOfBirth != null) { return true; }
        if (donorStatus != 0)    { return true; }
        return false;
    }

    function getDocType() as Number { return docType; }

    //! "None / Text Only" (docType 0) means no barcode should render at
    //! all, even if a national ID / doc string is configured.
    function hasDocument() as Boolean {
        if (docType == 0) { return false; }
        if (nationalId != null) { return true; }
        return docString != null;
    }
}
