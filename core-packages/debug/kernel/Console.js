/*

import Json.Encode as Encode exposing (Value)

*/

// ============================================================================
// Debug.Console Kernel - Proper JSON Console Logging for Canopy
// ============================================================================

// VALUE SERIALIZATION
// Converts Canopy/Elm values to plain JavaScript objects for console inspection

var _Console_toPlainObject = function(value, depth) {
    depth = depth || 0;

    // Prevent infinite recursion
    if (depth > 50) {
        return { __truncated__: 'Maximum depth exceeded' };
    }

    // Handle null/undefined
    if (value === null) return null;
    if (value === undefined) return undefined;

    // Handle primitives
    if (typeof value === 'boolean' || typeof value === 'number' || typeof value === 'string') {
        return value;
    }

    // Handle functions - show arity information
    if (typeof value === 'function') {
        if (value.a !== undefined && value.f !== undefined) {
            return '<function:' + value.a + ' args remaining>';
        }
        return '<function:' + value.length + '>';
    }

    // Handle Elm/Canopy String (boxed char)
    if (value instanceof String) {
        return String(value);
    }

    // Handle arrays
    if (Array.isArray(value)) {
        return value.map(function(item) {
            return _Console_toPlainObject(item, depth + 1);
        });
    }

    // Handle Elm/Canopy objects
    if (typeof value === 'object' && value !== null) {
        if ('$' in value) {
            return _Console_serializeTagged(value, depth);
        }
        return _Console_serializeRecord(value, depth);
    }

    return String(value);
};

var _Console_serializeTagged = function(value, depth) {
    var tag = value.$;

    // Handle numeric tags (production mode)
    if (typeof tag === 'number') {
        var fields = {};
        for (var key in value) {
            if (key !== '$') {
                fields[key] = _Console_toPlainObject(value[key], depth + 1);
            }
        }
        return { __tag__: tag, ...fields };
    }

    // Tuple (starts with #)
    if (typeof tag === 'string' && tag[0] === '#') {
        var tuple = [];
        for (var i = 0; i < 10; i++) {
            var key = String.fromCharCode(97 + i);
            if (key in value) tuple.push(_Console_toPlainObject(value[key], depth + 1));
        }
        return tuple;
    }

    // Maybe
    if (tag === 'Nothing') return null;
    if (tag === 'Just') return _Console_toPlainObject(value.a, depth + 1);

    // Result
    if (tag === 'Ok') return { Ok: _Console_toPlainObject(value.a, depth + 1) };
    if (tag === 'Err') return { Err: _Console_toPlainObject(value.a, depth + 1) };

    // List
    if (tag === '::' || tag === '[]') return _Console_serializeList(value, depth);

    // Dict
    if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin') {
        return _Console_serializeDict(value, depth);
    }

    // Set
    if (tag === 'Set_elm_builtin') {
        return _Console_serializeSet(value, depth);
    }

    // Generic custom type
    var result = { __constructor__: tag };
    ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'].forEach(function(f) {
        if (f in value) result[f] = _Console_toPlainObject(value[f], depth + 1);
    });
    return result;
};

var _Console_serializeList = function(value, depth) {
    var result = [];
    var current = value;
    var count = 0;
    while (current.$ === '::' && count < 10000) {
        result.push(_Console_toPlainObject(current.a, depth + 1));
        current = current.b;
        count++;
    }
    if (count >= 10000) result.push({ __truncated__: 'List too long' });
    return result;
};

var _Console_serializeRecord = function(value, depth) {
    var result = {};
    for (var key in value) {
        if (value.hasOwnProperty(key) && key !== '$') {
            result[key] = _Console_toPlainObject(value[key], depth + 1);
        }
    }
    return result;
};

var _Console_serializeDict = function(value, depth) {
    var entries = [];
    _Console_walkDict(value, function(k, v) {
        entries.push({ key: _Console_toPlainObject(k, depth + 1), value: _Console_toPlainObject(v, depth + 1) });
    });
    var allStringKeys = entries.every(function(e) { return typeof e.key === 'string'; });
    if (allStringKeys) {
        var obj = {};
        entries.forEach(function(e) { obj[e.key] = e.value; });
        return obj;
    }
    return entries;
};

var _Console_walkDict = function(dict, callback) {
    if (dict.$ === 'RBEmpty_elm_builtin') return;
    if (dict.$ === 'RBNode_elm_builtin') {
        _Console_walkDict(dict.d, callback);
        callback(dict.b, dict.c);
        _Console_walkDict(dict.e, callback);
    }
};

var _Console_serializeSet = function(value, depth) {
    var result = [];
    _Console_walkDict(value.a, function(k) {
        result.push(_Console_toPlainObject(k, depth + 1));
    });
    return result;
};

// CONSOLE LOGGING FUNCTIONS

var _Console_log = F2(function(tag, value) {
    var plain = _Console_toPlainObject(value, 0);
    console.log('%c' + tag + ':', 'color: #666; font-weight: bold', plain);
    return value;
});

var _Console_logJson = F2(function(tag, value) {
    console.log('%c' + tag + ':', 'color: #666; font-weight: bold', value);
    return value;
});

var _Console_warn = F2(function(tag, value) {
    var plain = _Console_toPlainObject(value, 0);
    console.warn('%c' + tag + ':', 'color: #856404; font-weight: bold', plain);
    return value;
});

var _Console_error = F2(function(tag, value) {
    var plain = _Console_toPlainObject(value, 0);
    console.error('%c' + tag + ':', 'color: #721c24; font-weight: bold', plain);
    return value;
});

var _Console_table = F2(function(tag, value) {
    var plain = _Console_toPlainObject(value, 0);
    console.log('%c' + tag + ':', 'color: #666; font-weight: bold');
    console.table(Array.isArray(plain) ? plain : [plain]);
    return value;
});

var _Console_group = function(label) {
    console.group(label);
    return 0;
};

var _Console_groupEnd = function(_v) {
    console.groupEnd();
    return 0;
};

var _Console_time = function(label) {
    console.time(label);
    return 0;
};

var _Console_timeEnd = function(label) {
    console.timeEnd(label);
    return 0;
};

var _Console_inspect = F2(function(tag, value) {
    var inspected = _Console_inspectValue(value, 0);
    console.log('%c' + tag + ' (inspected):', 'color: #6c5ce7; font-weight: bold', inspected);
    return value;
});

var _Console_inspectValue = function(value, depth) {
    if (depth > 50) return { __truncated__: true };
    if (value === null) return { __type__: 'null', value: null };
    if (value === undefined) return { __type__: 'undefined' };
    if (typeof value === 'boolean') return { __type__: 'Bool', value: value };
    if (typeof value === 'number') {
        return Number.isInteger(value)
            ? { __type__: 'Int', value: value }
            : { __type__: 'Float', value: value };
    }
    if (typeof value === 'string') return { __type__: 'String', value: value };
    if (value instanceof String) return { __type__: 'Char', value: String(value) };
    if (typeof value === 'function') {
        if (value.a !== undefined && value.f !== undefined) {
            return {
                __type__: 'PartiallyAppliedFunction',
                argsRemaining: value.a,
                note: 'This function is missing ' + value.a + ' argument(s)'
            };
        }
        return { __type__: 'Function', arity: value.length };
    }
    if (Array.isArray(value)) {
        return {
            __type__: 'Array',
            length: value.length,
            items: value.map(function(item) { return _Console_inspectValue(item, depth + 1); })
        };
    }
    if (typeof value === 'object' && '$' in value) {
        return _Console_inspectTagged(value, depth);
    }
    if (typeof value === 'object') {
        var obj = { __type__: 'Record', fields: {} };
        for (var key in value) {
            if (value.hasOwnProperty(key)) {
                obj.fields[key] = _Console_inspectValue(value[key], depth + 1);
            }
        }
        return obj;
    }
    return { __type__: 'Unknown', value: String(value) };
};

var _Console_inspectTagged = function(value, depth) {
    var tag = value.$;
    if (tag === 'Nothing') return { __type__: 'Maybe', variant: 'Nothing' };
    if (tag === 'Just') return { __type__: 'Maybe', variant: 'Just', value: _Console_inspectValue(value.a, depth + 1) };
    if (tag === 'Ok') return { __type__: 'Result', variant: 'Ok', value: _Console_inspectValue(value.a, depth + 1) };
    if (tag === 'Err') return { __type__: 'Result', variant: 'Err', error: _Console_inspectValue(value.a, depth + 1) };
    if (tag === '::' || tag === '[]') {
        var list = _Console_serializeList(value, depth);
        return { __type__: 'List', length: list.length, items: list };
    }
    if (typeof tag === 'string' && tag[0] === '#') {
        var tuple = _Console_serializeTagged(value, depth);
        return { __type__: 'Tuple' + tag.substring(1), values: tuple };
    }
    var fields = {};
    for (var key in value) {
        if (key !== '$') fields[key] = _Console_inspectValue(value[key], depth + 1);
    }
    return { __type__: 'CustomType', constructor: tag, fields: fields };
};
