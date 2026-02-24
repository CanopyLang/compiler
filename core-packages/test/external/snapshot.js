/**
 * Canopy Snapshot Testing - JavaScript Implementation
 *
 * This module provides snapshot comparison for the Canopy test framework.
 * Snapshots are stored as text files in tests/__snapshots__/ and compared
 * against actual values at test time.
 *
 * @module snapshot
 */

var _snapshotDir = 'tests/__snapshots__';

/**
 * Read the update mode from the CLI-injected global.
 * When --update-snapshots is passed, the runner sets this flag.
 */
var _updateMode = (typeof global !== 'undefined' && global.__CANOPY_UPDATE_SNAPSHOTS__)
    ? true
    : false;

/**
 * Load all snapshots from a module's snapshot file.
 * @param {string} moduleName - The module whose snapshots to load
 * @returns {Object} Map of snapshot name to stored value
 */
function loadSnapshotFile(moduleName) {
    try {
        var fs = require('fs');
        var path = _snapshotDir + '/' + moduleName + '.snap';
        if (!fs.existsSync(path)) return {};
        var content = fs.readFileSync(path, 'utf8');
        return parseSnapFile(content);
    } catch (e) {
        return {};
    }
}

/**
 * Parse a snapshot file into name-value pairs.
 * Format: "-- Snapshot: name\nvalue\n\n"
 * @param {string} content - Raw file content
 * @returns {Object} Map of snapshot name to stored value
 */
function parseSnapFile(content) {
    var result = {};
    var sections = content.split('\n-- Snapshot: ');
    for (var i = 0; i < sections.length; i++) {
        var section = sections[i].trim();
        if (!section) continue;
        var newline = section.indexOf('\n');
        if (newline === -1) continue;
        var name = section.substring(0, newline).trim();
        var value = section.substring(newline + 1).trim();
        result[name] = value;
    }
    return result;
}

/**
 * Save snapshots to a module's snapshot file.
 * Creates the __snapshots__ directory if needed.
 * @param {string} moduleName - The module whose snapshots to save
 * @param {Object} snapshots - Map of snapshot name to value
 */
function saveSnapshotFile(moduleName, snapshots) {
    try {
        var fs = require('fs');
        fs.mkdirSync(_snapshotDir, { recursive: true });
        var path = _snapshotDir + '/' + moduleName + '.snap';
        var content = '';
        var names = Object.keys(snapshots).sort();
        for (var i = 0; i < names.length; i++) {
            content += '-- Snapshot: ' + names[i] + '\n';
            content += snapshots[names[i]] + '\n\n';
        }
        fs.writeFileSync(path, content, 'utf8');
    } catch (e) {
        // Ignore write errors in read-only environments
    }
}

/**
 * Match a value against its stored snapshot.
 *
 * On first run or when update mode is active, the snapshot is saved.
 * On subsequent runs, the value is compared against the stored snapshot.
 *
 * Returns a Canopy Expectation value:
 *   { $: 'Pass' } on match
 *   { $: 'Fail', a: { $: 'Equality', a: label, b: expected, c: actual } } on mismatch
 *
 * @canopy-type String -> String -> String -> Expectation
 * @name match
 * @param {string} moduleName - Module name for the snapshot file
 * @param {string} name - Snapshot identifier within the file
 * @param {string} value - Actual value to compare
 * @returns {Object} Canopy Expectation
 */
function match(moduleName, name, value) {
    var snapshots = loadSnapshotFile(moduleName);
    var stored = snapshots[name];

    if (_updateMode || stored === undefined) {
        snapshots[name] = value;
        saveSnapshotFile(moduleName, snapshots);
        return { $: 'Pass' };
    }

    if (stored === value) {
        return { $: 'Pass' };
    }

    return {
        $: 'Fail',
        a: {
            $: 'Equality',
            a: 'Snapshot mismatch for "' + name + '"',
            b: stored,
            c: value
        }
    };
}

// Export for Node.js
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        match: match
    };
}

// Make available globally for FFI
if (typeof window !== 'undefined') {
    window.CanopySnapshot = {
        match: match
    };
}
