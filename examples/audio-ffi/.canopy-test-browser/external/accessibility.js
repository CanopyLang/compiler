/**
 * Canopy Accessibility Testing FFI (axe-core)
 *
 * This module provides accessibility testing capabilities using axe-core.
 * All functions follow Canopy FFI conventions with @canopy-type annotations.
 *
 * Features:
 * - Full page accessibility audits
 * - Element-specific audits
 * - WCAG compliance checking (A, AA, AAA)
 * - Specific rule checking (labels, contrast, headings, etc.)
 *
 * @module accessibility
 */

// ============================================================================
// Audit Functions
// ============================================================================

/**
 * Run full accessibility audit on current page
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name audit
 * @param {Object} browser - Browser handle from playwright.js
 * @returns {Promise<Object>} Audit results with violations, passes, incomplete
 */
async function audit(browser) {
    // Inject axe-core if not already present
    await injectAxe(browser._page);

    // Run audit
    const results = await browser._page.evaluate(async () => {
        return await window.axe.run();
    });

    return formatResults(results);
}

/**
 * Run accessibility audit on specific element
 * @canopy-type String -> Browser -> Task AuditError AuditResult
 * @name auditElement
 * @param {string} selector - CSS selector for element to audit
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for that element
 */
async function auditElement(selector, browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async (sel) => {
        const element = document.querySelector(sel);
        if (!element) {
            throw new Error(`Element not found: ${sel}`);
        }
        return await window.axe.run(element);
    }, selector);

    return formatResults(results);
}

/**
 * Run accessibility audit with specific rules only
 * @canopy-type List String -> Browser -> Task AuditError AuditResult
 * @name auditWithRules
 * @param {string[]} rules - List of rule IDs to run (e.g., ["color-contrast", "label"])
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results
 */
async function auditWithRules(rules, browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async (ruleIds) => {
        return await window.axe.run({
            runOnly: {
                type: 'rule',
                values: ruleIds
            }
        });
    }, rules);

    return formatResults(results);
}

/**
 * Run accessibility audit excluding specific rules
 * @canopy-type List String -> Browser -> Task AuditError AuditResult
 * @name auditExcluding
 * @param {string[]} rules - List of rule IDs to exclude
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results
 */
async function auditExcluding(rules, browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async (excludeRules) => {
        return await window.axe.run({
            rules: excludeRules.reduce((acc, rule) => {
                acc[rule] = { enabled: false };
                return acc;
            }, {})
        });
    }, rules);

    return formatResults(results);
}

// ============================================================================
// WCAG Compliance
// ============================================================================

/**
 * Check WCAG 2.1 Level A compliance
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkWcagA
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for Level A
 */
async function checkWcagA(browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async () => {
        return await window.axe.run({
            runOnly: {
                type: 'tag',
                values: ['wcag2a', 'wcag21a']
            }
        });
    });

    return formatResults(results);
}

/**
 * Check WCAG 2.1 Level AA compliance
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkWcagAA
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for Level AA
 */
async function checkWcagAA(browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async () => {
        return await window.axe.run({
            runOnly: {
                type: 'tag',
                values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']
            }
        });
    });

    return formatResults(results);
}

/**
 * Check WCAG 2.1 Level AAA compliance
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkWcagAAA
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for Level AAA
 */
async function checkWcagAAA(browser) {
    await injectAxe(browser._page);

    const results = await browser._page.evaluate(async () => {
        return await window.axe.run({
            runOnly: {
                type: 'tag',
                values: ['wcag2a', 'wcag2aa', 'wcag2aaa', 'wcag21a', 'wcag21aa', 'wcag21aaa']
            }
        });
    });

    return formatResults(results);
}

// ============================================================================
// Specific Checks
// ============================================================================

/**
 * Check form labels accessibility
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkLabels
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for label-related rules
 */
async function checkLabels(browser) {
    return auditWithRules(['label', 'label-title-only', 'label-content-name-mismatch'], browser);
}

/**
 * Check color contrast accessibility
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkContrast
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for contrast rules
 */
async function checkContrast(browser) {
    return auditWithRules(['color-contrast', 'color-contrast-enhanced'], browser);
}

/**
 * Check heading structure
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkHeadings
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for heading rules
 */
async function checkHeadings(browser) {
    return auditWithRules(['heading-order', 'empty-heading', 'page-has-heading-one'], browser);
}

/**
 * Check landmark regions
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkLandmarks
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for landmark rules
 */
async function checkLandmarks(browser) {
    return auditWithRules([
        'landmark-banner-is-top-level',
        'landmark-contentinfo-is-top-level',
        'landmark-main-is-top-level',
        'landmark-no-duplicate-banner',
        'landmark-no-duplicate-contentinfo',
        'landmark-no-duplicate-main',
        'landmark-one-main',
        'landmark-unique',
        'region'
    ], browser);
}

/**
 * Check ARIA attributes
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkAria
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for ARIA rules
 */
async function checkAria(browser) {
    return auditWithRules([
        'aria-allowed-attr',
        'aria-allowed-role',
        'aria-command-name',
        'aria-dialog-name',
        'aria-hidden-body',
        'aria-hidden-focus',
        'aria-input-field-name',
        'aria-meter-name',
        'aria-progressbar-name',
        'aria-required-attr',
        'aria-required-children',
        'aria-required-parent',
        'aria-roledescription',
        'aria-roles',
        'aria-toggle-field-name',
        'aria-tooltip-name',
        'aria-valid-attr',
        'aria-valid-attr-value'
    ], browser);
}

/**
 * Check keyboard accessibility
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkKeyboard
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for keyboard rules
 */
async function checkKeyboard(browser) {
    return auditWithRules([
        'accesskeys',
        'focus-order-semantics',
        'focusable-disabled',
        'focusable-no-name',
        'frame-focusable-content',
        'scrollable-region-focusable',
        'skip-link',
        'tabindex'
    ], browser);
}

/**
 * Check image accessibility (alt text, etc.)
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkImages
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for image rules
 */
async function checkImages(browser) {
    return auditWithRules([
        'image-alt',
        'image-redundant-alt',
        'input-image-alt',
        'role-img-alt',
        'svg-img-alt'
    ], browser);
}

/**
 * Check link accessibility
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkLinks
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for link rules
 */
async function checkLinks(browser) {
    return auditWithRules([
        'link-name',
        'link-in-text-block',
        'identical-links-same-purpose'
    ], browser);
}

/**
 * Check table accessibility
 * @canopy-type Browser -> Task AuditError AuditResult
 * @name checkTables
 * @param {Object} browser - Browser handle
 * @returns {Promise<Object>} Audit results for table rules
 */
async function checkTables(browser) {
    return auditWithRules([
        'table-duplicate-name',
        'table-fake-caption',
        'td-has-header',
        'td-headers-attr',
        'th-has-data-cells'
    ], browser);
}

// ============================================================================
// Result Analysis
// ============================================================================

/**
 * Get count of violations by impact level
 * @canopy-type String -> AuditResult -> Int
 * @name violationCount
 * @param {string} impact - Impact level: "critical", "serious", "moderate", "minor"
 * @param {Object} result - Audit result from audit() or similar
 * @returns {number} Count of violations at that level
 */
function violationCount(impact, result) {
    return result.violations.filter(v => v.impact === impact).length;
}

/**
 * Get total count of all violations
 * @canopy-type AuditResult -> Int
 * @name totalViolations
 * @param {Object} result - Audit result
 * @returns {number} Total violation count
 */
function totalViolations(result) {
    return result.violations.length;
}

/**
 * Check if audit passed (no violations)
 * @canopy-type AuditResult -> Bool
 * @name passed
 * @param {Object} result - Audit result
 * @returns {boolean} True if no violations
 */
function passed(result) {
    return result.violations.length === 0;
}

/**
 * Check if audit has critical violations
 * @canopy-type AuditResult -> Bool
 * @name hasCritical
 * @param {Object} result - Audit result
 * @returns {boolean} True if has critical violations
 */
function hasCritical(result) {
    return result.violations.some(v => v.impact === 'critical');
}

/**
 * Check if audit has serious or critical violations
 * @canopy-type AuditResult -> Bool
 * @name hasSerious
 * @param {Object} result - Audit result
 * @returns {boolean} True if has serious or critical violations
 */
function hasSerious(result) {
    return result.violations.some(v => v.impact === 'critical' || v.impact === 'serious');
}

/**
 * Get violations filtered by impact level
 * @canopy-type String -> AuditResult -> List Violation
 * @name violationsOfImpact
 * @param {string} impact - Impact level to filter by
 * @param {Object} result - Audit result
 * @returns {Array} Filtered violations
 */
function violationsOfImpact(impact, result) {
    return result.violations.filter(v => v.impact === impact);
}

/**
 * Get violations filtered by rule ID
 * @canopy-type String -> AuditResult -> List Violation
 * @name violationsOfRule
 * @param {string} ruleId - Rule ID to filter by
 * @param {Object} result - Audit result
 * @returns {Array} Filtered violations
 */
function violationsOfRule(ruleId, result) {
    return result.violations.filter(v => v.id === ruleId);
}

/**
 * Format violations as human-readable string
 * @canopy-type AuditResult -> String
 * @name formatViolations
 * @param {Object} result - Audit result
 * @returns {string} Formatted violation report
 */
function formatViolations(result) {
    if (result.violations.length === 0) {
        return "No accessibility violations found.";
    }

    const lines = [`Found ${result.violations.length} accessibility violation(s):\n`];

    result.violations.forEach((v, i) => {
        lines.push(`${i + 1}. [${v.impact.toUpperCase()}] ${v.id}`);
        lines.push(`   ${v.help}`);
        lines.push(`   Help: ${v.helpUrl}`);
        lines.push(`   Affected elements:`);
        v.nodes.forEach(node => {
            lines.push(`   - ${node.selector}`);
            if (node.failureSummary) {
                lines.push(`     ${node.failureSummary.split('\n')[0]}`);
            }
        });
        lines.push('');
    });

    return lines.join('\n');
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Inject axe-core into page if not already present
 * @private
 */
async function injectAxe(page) {
    const hasAxe = await page.evaluate(() => typeof window.axe !== 'undefined');

    if (!hasAxe) {
        // Try local node_modules first, fall back to CDN
        try {
            const axeSource = require('axe-core').source;
            await page.evaluate(axeSource);
        } catch (e) {
            // Fall back to CDN
            await page.addScriptTag({
                url: 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.8.2/axe.min.js'
            });
            // Wait for script to load
            await page.waitForFunction(() => typeof window.axe !== 'undefined');
        }
    }
}

/**
 * Format axe-core results into Canopy-friendly structure
 * @private
 */
function formatResults(results) {
    return {
        violations: results.violations.map(v => ({
            id: v.id,
            impact: v.impact || 'minor',
            description: v.description,
            help: v.help,
            helpUrl: v.helpUrl,
            nodes: v.nodes.map(n => ({
                selector: n.target.join(' '),
                html: n.html,
                failureSummary: n.failureSummary || ''
            }))
        })),
        passes: results.passes.length,
        incomplete: results.incomplete.length,
        inapplicable: results.inapplicable.length
    };
}

// ============================================================================
// Module Exports
// ============================================================================

module.exports = {
    // Main audit functions
    audit,
    auditElement,
    auditWithRules,
    auditExcluding,

    // WCAG compliance
    checkWcagA,
    checkWcagAA,
    checkWcagAAA,

    // Specific checks
    checkLabels,
    checkContrast,
    checkHeadings,
    checkLandmarks,
    checkAria,
    checkKeyboard,
    checkImages,
    checkLinks,
    checkTables,

    // Result analysis
    violationCount,
    totalViolations,
    passed,
    hasCritical,
    hasSerious,
    violationsOfImpact,
    violationsOfRule,
    formatViolations
};
