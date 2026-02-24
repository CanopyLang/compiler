/**
 * Canopy Component Testing - JavaScript Implementation
 *
 * Provides jsdom-based DOM rendering, event dispatch, and querying
 * for the Canopy component testing framework.
 *
 * Requires: jsdom (installed as devDependency)
 *
 * @module component
 */

var _jsdom = null;

/**
 * Lazily load jsdom to avoid requiring it when not running component tests.
 */
function getJSDOM() {
    if (_jsdom) return _jsdom;
    try {
        _jsdom = require('jsdom');
    } catch (e) {
        throw new Error(
            'Component testing requires jsdom. Install it with: npm install --save-dev jsdom'
        );
    }
    return _jsdom;
}

/**
 * Convert a Canopy VirtualDom node to an HTML string.
 *
 * Canopy/Elm VirtualDom structure:
 *   Node: { $: 0 | 1 | 2 | 3, ... }
 *     0 = element node (a=tag, b=attrList, c=childList, d=namespace)
 *     1 = text node (a=text)
 *     2 = keyed node
 *     3 = custom/tagger
 *
 * @param {Object} vdom - Canopy VirtualDom node
 * @returns {string} HTML string
 */
function vdomToHtml(vdom) {
    if (!vdom) return '';

    switch (vdom.$) {
        case 0: // Element node
        case 1: // Keyed element
            return renderElementNode(vdom);

        case 2: // Text node
            return escapeHtml(typeof vdom.a === 'string' ? vdom.a : String(vdom.a));

        case 3: // Tagger (wraps messages)
            return vdomToHtml(vdom.b);

        default:
            // Try to handle as text if it has an 'a' property
            if (typeof vdom === 'string') return escapeHtml(vdom);
            if (typeof vdom.a === 'string' && vdom.$ === undefined) return escapeHtml(vdom.a);
            return '';
    }
}

/**
 * Render an element node to HTML.
 */
function renderElementNode(vdom) {
    var tag = vdom.a || 'div';
    var attrs = renderAttributes(vdom.b);
    var children = renderChildren(vdom.c);

    var selfClosing = ['br', 'hr', 'img', 'input', 'meta', 'link'];
    if (selfClosing.indexOf(tag) !== -1 && !children) {
        return '<' + tag + attrs + ' />';
    }

    return '<' + tag + attrs + '>' + children + '</' + tag + '>';
}

/**
 * Render attribute list to HTML attribute string.
 */
function renderAttributes(attrList) {
    if (!attrList) return '';
    var result = '';
    var current = attrList;

    while (current && current.$ === '::') {
        var attr = current.a;
        result += renderSingleAttribute(attr);
        current = current.b;
    }

    return result;
}

/**
 * Render a single attribute to HTML.
 */
function renderSingleAttribute(attr) {
    if (!attr) return '';

    // Property attribute: { $: 'a0', a: key, b: value }
    if (attr.$ === 'a0') {
        return ' ' + attr.a + '="' + escapeAttr(String(attr.b)) + '"';
    }
    // Style attribute: { $: 'a1', a: key, b: value }
    if (attr.$ === 'a1') {
        return ' style="' + attr.a + ':' + escapeAttr(attr.b) + '"';
    }
    // Event attribute: { $: 'a2', ... } — skip for HTML rendering
    if (attr.$ === 'a2') return '';

    // Generic: just try key/value
    if (attr.a && attr.b !== undefined) {
        return ' ' + attr.a + '="' + escapeAttr(String(attr.b)) + '"';
    }

    return '';
}

/**
 * Render children list to HTML.
 */
function renderChildren(childList) {
    if (!childList) return '';
    var result = '';
    var current = childList;

    while (current && current.$ === '::') {
        result += vdomToHtml(current.a);
        current = current.b;
    }

    return result;
}

/**
 * Escape HTML special characters.
 */
function escapeHtml(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

/**
 * Escape attribute value.
 */
function escapeAttr(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;');
}

/**
 * Collect event handlers from VirtualDom attributes.
 */
function collectHandlers(attrList) {
    var handlers = {};
    var current = attrList;

    while (current && current.$ === '::') {
        var attr = current.a;
        if (attr && attr.$ === 'a2') {
            handlers[attr.a] = attr.b;
        }
        current = current.b;
    }

    return handlers;
}

/**
 * Collect all event handlers from a vdom tree.
 */
function collectAllHandlers(vdom) {
    var all = {};
    if (!vdom) return all;

    if (vdom.$ === 0 || vdom.$ === 1) {
        var handlers = collectHandlers(vdom.b);
        for (var key in handlers) {
            all[key] = handlers[key];
        }
        var current = vdom.c;
        while (current && current.$ === '::') {
            var childHandlers = collectAllHandlers(current.a);
            for (var ck in childHandlers) {
                if (!all[ck]) all[ck] = childHandlers[ck];
            }
            current = current.b;
        }
    }

    if (vdom.$ === 3) {
        var inner = collectAllHandlers(vdom.b);
        for (var ik in inner) {
            all[ik] = inner[ik];
        }
    }

    return all;
}

/**
 * Create a Canopy list from a JS array.
 */
function arrayToList(arr) {
    var result = { $: '[]' };
    for (var i = arr.length - 1; i >= 0; i--) {
        result = { $: '::', a: arr[i], b: result };
    }
    return result;
}

/**
 * Convert a Canopy list to a JS array.
 */
function listToArray(list) {
    var result = [];
    var current = list;
    while (current && current.$ === '::') {
        result.push(current.a);
        current = current.b;
    }
    return result;
}

/**
 * Render an Html value to a Rendered component state.
 *
 * @canopy-type Html msg -> Rendered msg
 * @name render
 * @param {Object} html - Canopy Html VirtualDom node
 * @returns {Object} Rendered component
 */
function render(html) {
    var htmlStr = vdomToHtml(html);
    var handlers = collectAllHandlers(html);

    return {
        $: 'Rendered',
        a: {
            html: htmlStr,
            messages: { $: '[]' },
            model: { $: 'Nothing' },
            _vdom: html,
            _handlers: handlers,
            _dom: createDom(htmlStr)
        }
    };
}

/**
 * Create a jsdom document from HTML.
 */
function createDom(htmlStr) {
    try {
        var JSDOM = getJSDOM().JSDOM;
        var dom = new JSDOM('<body>' + htmlStr + '</body>');
        return dom.window.document.body;
    } catch (e) {
        return null;
    }
}

/**
 * Render with an initial model.
 *
 * @canopy-type model -> (model -> Html msg) -> Rendered msg
 * @name renderWithModel
 */
function renderWithModel(model, viewFn) {
    var html = viewFn(model);
    var result = render(html);
    result.a.model = { $: 'Just', a: model };
    result.a._model = model;
    result.a._viewFn = viewFn;
    return result;
}

/**
 * Dispatch an event and collect messages.
 */
function dispatchEvent(eventName, eventData, rendered) {
    var handlers = rendered.a._handlers || {};
    var handler = handlers[eventName];
    var messages = listToArray(rendered.a.messages);

    if (handler) {
        try {
            var event = eventData || {};
            var msg = typeof handler === 'function' ? handler(event) : handler;
            messages.push(msg);
        } catch (e) {
            // Handler invocation failed; continue without message
        }
    }

    return {
        $: 'Rendered',
        a: {
            html: rendered.a.html,
            messages: arrayToList(messages),
            model: rendered.a.model,
            _vdom: rendered.a._vdom,
            _handlers: rendered.a._handlers,
            _dom: rendered.a._dom
        }
    };
}

/**
 * Simulate a click event.
 *
 * @canopy-type Rendered msg -> Rendered msg
 * @name click
 */
function click(rendered) {
    return dispatchEvent('click', {}, rendered);
}

/**
 * Simulate an input event.
 *
 * @canopy-type String -> Rendered msg -> Rendered msg
 * @name input
 */
function inputEvent(value, rendered) {
    return dispatchEvent('input', { target: { value: value } }, rendered);
}

/**
 * Simulate a change event.
 *
 * @canopy-type String -> Rendered msg -> Rendered msg
 * @name change
 */
function changeEvent(value, rendered) {
    return dispatchEvent('change', { target: { value: value } }, rendered);
}

/**
 * Simulate a submit event.
 *
 * @canopy-type Rendered msg -> Rendered msg
 * @name submit
 */
function submitEvent(rendered) {
    return dispatchEvent('submit', {}, rendered);
}

/**
 * Simulate a focus event.
 *
 * @canopy-type Rendered msg -> Rendered msg
 * @name focus
 */
function focusEvent(rendered) {
    return dispatchEvent('focus', {}, rendered);
}

/**
 * Simulate a blur event.
 *
 * @canopy-type Rendered msg -> Rendered msg
 * @name blur
 */
function blurEvent(rendered) {
    return dispatchEvent('blur', {}, rendered);
}

/**
 * Simulate a keydown event.
 *
 * @canopy-type String -> Rendered msg -> Rendered msg
 * @name keyDown
 */
function keyDown(key, rendered) {
    return dispatchEvent('keydown', { key: key }, rendered);
}

/**
 * Simulate a keyup event.
 *
 * @canopy-type String -> Rendered msg -> Rendered msg
 * @name keyUp
 */
function keyUp(key, rendered) {
    return dispatchEvent('keyup', { key: key }, rendered);
}

/**
 * Simulate a keypress event.
 *
 * @canopy-type String -> Rendered msg -> Rendered msg
 * @name keyPress
 */
function keyPress(key, rendered) {
    return dispatchEvent('keypress', { key: key }, rendered);
}

/**
 * Convert a DOM element to a Canopy Element.
 */
function domToElement(domEl) {
    var attrs = [];
    if (domEl.attributes) {
        for (var i = 0; i < domEl.attributes.length; i++) {
            var a = domEl.attributes[i];
            attrs.push({ $: '::', a: { $: 'Tuple2', a: a.name, b: a.value }, b: { $: '[]' } });
        }
    }

    var children = [];
    if (domEl.children) {
        for (var j = 0; j < domEl.children.length; j++) {
            children.push(domToElement(domEl.children[j]));
        }
    }

    return {
        $: 'Element',
        a: {
            tagName: domEl.tagName ? domEl.tagName.toLowerCase() : '',
            attributes: arrayToList(attrs.map(function(pair) { return pair.a; })),
            textContent: domEl.textContent || '',
            children: arrayToList(children)
        }
    };
}

/**
 * Find elements matching a CSS selector.
 *
 * @canopy-type String -> Rendered msg -> QueryResult msg
 * @name find
 */
function find(selector, rendered) {
    var dom = rendered.a._dom;
    var elements = [];

    if (dom) {
        try {
            var nodeList = dom.querySelectorAll(selector);
            for (var i = 0; i < nodeList.length; i++) {
                elements.push(domToElement(nodeList[i]));
            }
        } catch (e) {
            // Invalid selector; return empty
        }
    }

    return {
        $: 'QueryResult',
        a: {
            elements: arrayToList(elements),
            rendered: rendered
        }
    };
}

// Export for Node.js
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        render: render,
        renderWithModel: renderWithModel,
        click: click,
        input: inputEvent,
        change: changeEvent,
        submit: submitEvent,
        focus: focusEvent,
        blur: blurEvent,
        keyDown: keyDown,
        keyUp: keyUp,
        keyPress: keyPress,
        find: find
    };
}

// Make available globally for FFI
if (typeof window !== 'undefined') {
    window.CanopyComponent = module.exports;
}
