/**
 * Canopy Task Executor Engine
 *
 * This module provides JavaScript runtime execution for Canopy Task types.
 * Tasks are the IO monad in Canopy - they represent asynchronous computations
 * that may fail.
 *
 * Task Constructor Tags (from compiled output):
 *   $: 0 = SUCCEED  - Success value (value in .a)
 *   $: 1 = FAIL     - Failure value (error in .a)
 *   $: 2 = BINDING  - Async callback (callback in .b, kill in .c)
 *   $: 3 = AND_THEN - Chain tasks (callback in .b, task in .d)
 *   $: 4 = ON_ERROR - Error handler (callback in .b, task in .d)
 *   $: 5 = RECEIVE  - Process mailbox (callback in .b) - not used in browser tests
 *
 * @module task-executor
 */

// Task constructor tags
const SUCCEED = 0;
const FAIL = 1;
const BINDING = 2;
const AND_THEN = 3;
const ON_ERROR = 4;
const RECEIVE = 5;

/**
 * Execute a Canopy Task and return a Promise.
 *
 * This is the core execution engine that unwraps Task constructors
 * and executes them as JavaScript Promises.
 *
 * @canopy-type Task err a -> Promise a
 * @param {Object} task - A Canopy Task value
 * @returns {Promise<*>} Promise that resolves with the task result
 * @throws {*} The error value if the task fails
 */
async function executeTask(task) {
    // Handle null/undefined gracefully
    if (!task) {
        throw new Error('Task is null or undefined');
    }

    // Handle non-task values (already resolved)
    if (typeof task.$ !== 'number') {
        return task;
    }

    switch (task.$) {
        case SUCCEED:
            // Task succeeded with value
            return task.a;

        case FAIL:
            // Task failed with error
            throw task.a;

        case BINDING:
            // Async operation - convert callback to Promise
            return await executeBinding(task);

        case AND_THEN:
            // Chain: execute inner task, then apply callback
            return await executeAndThen(task);

        case ON_ERROR:
            // Error handler: try inner task, catch with callback
            return await executeOnError(task);

        case RECEIVE:
            // Process mailbox - not supported in standalone execution
            throw new Error('RECEIVE tasks require a process context');

        default:
            throw new Error('Unknown Task constructor: ' + task.$);
    }
}

/**
 * Execute a BINDING task (async callback).
 *
 * BINDING wraps a callback-based async operation.
 * The callback receives a function to call with the result.
 *
 * @param {Object} task - BINDING task with .b = callback
 * @returns {Promise<*>}
 */
async function executeBinding(task) {
    return new Promise((resolve, reject) => {
        try {
            // The callback receives a function that takes the next task
            const kill = task.b(function(resultTask) {
                // resultTask is either SUCCEED or FAIL
                if (resultTask.$ === SUCCEED) {
                    resolve(resultTask.a);
                } else if (resultTask.$ === FAIL) {
                    reject(resultTask.a);
                } else {
                    // Result is another task - execute it
                    executeTask(resultTask)
                        .then(resolve)
                        .catch(reject);
                }
            });

            // Store kill function if provided
            if (kill && task.c === null) {
                task.c = kill;
            }
        } catch (e) {
            reject(e);
        }
    });
}

/**
 * Execute an AND_THEN task (monadic bind).
 *
 * Executes the inner task, then applies the callback to get the next task.
 *
 * @param {Object} task - AND_THEN task with .b = callback, .d = inner task
 * @returns {Promise<*>}
 */
async function executeAndThen(task) {
    // Execute the inner task first
    const innerResult = await executeTask(task.d);

    // Apply the callback to get the next task
    const nextTask = task.b(innerResult);

    // Execute the next task
    return await executeTask(nextTask);
}

/**
 * Execute an ON_ERROR task (error recovery).
 *
 * Tries to execute the inner task. If it fails, applies the error callback.
 *
 * @param {Object} task - ON_ERROR task with .b = error callback, .d = inner task
 * @returns {Promise<*>}
 */
async function executeOnError(task) {
    try {
        // Try to execute the inner task
        return await executeTask(task.d);
    } catch (error) {
        // On error, apply the callback to get a recovery task
        const recoveryTask = task.b(error);

        // Execute the recovery task
        return await executeTask(recoveryTask);
    }
}

/**
 * Create a SUCCEED task.
 *
 * @param {*} value - The success value
 * @returns {Object} SUCCEED task
 */
function succeed(value) {
    return { $: SUCCEED, a: value };
}

/**
 * Create a FAIL task.
 *
 * @param {*} error - The error value
 * @returns {Object} FAIL task
 */
function fail(error) {
    return { $: FAIL, a: error };
}

/**
 * Create a BINDING task from a Promise.
 *
 * This converts a JavaScript Promise into a Canopy Task.
 *
 * @param {Promise<*>} promise - JavaScript Promise
 * @returns {Object} BINDING task
 */
function fromPromise(promise) {
    return {
        $: BINDING,
        b: function(callback) {
            promise
                .then(value => callback(succeed(value)))
                .catch(error => callback(fail(error)));
            return null; // No kill function
        },
        c: null
    };
}

/**
 * Create a BINDING task from an async function.
 *
 * @param {Function} asyncFn - Async function to execute
 * @returns {Object} BINDING task
 */
function fromAsync(asyncFn) {
    return {
        $: BINDING,
        b: function(callback) {
            asyncFn()
                .then(value => callback(succeed(value)))
                .catch(error => callback(fail(error)));
            return null;
        },
        c: null
    };
}

/**
 * Chain two tasks (andThen).
 *
 * @param {Function} callback - Function (a -> Task err b)
 * @param {Object} task - Inner task
 * @returns {Object} AND_THEN task
 */
function andThen(callback, task) {
    return { $: AND_THEN, b: callback, d: task };
}

/**
 * Handle errors in a task.
 *
 * @param {Function} callback - Error handler (err -> Task err2 a)
 * @param {Object} task - Inner task
 * @returns {Object} ON_ERROR task
 */
function onError(callback, task) {
    return { $: ON_ERROR, b: callback, d: task };
}

/**
 * Map over a task result.
 *
 * @param {Function} fn - Function (a -> b)
 * @param {Object} task - Task to map over
 * @returns {Object} Mapped task
 */
function map(fn, task) {
    return andThen(function(value) {
        return succeed(fn(value));
    }, task);
}

/**
 * Execute a task and return a Result instead of throwing.
 *
 * @param {Object} task - Task to execute
 * @returns {Promise<Object>} Promise of Result (Ok or Err)
 */
async function attempt(task) {
    try {
        const value = await executeTask(task);
        return { $: 'Ok', a: value };
    } catch (error) {
        return { $: 'Err', a: error };
    }
}

/**
 * Execute multiple tasks in sequence.
 *
 * @param {Array<Object>} tasks - Array of tasks
 * @returns {Promise<Array<*>>} Promise of results array
 */
async function sequence(tasks) {
    const results = [];
    for (const task of tasks) {
        results.push(await executeTask(task));
    }
    return results;
}

/**
 * Execute multiple tasks in parallel.
 *
 * @param {Array<Object>} tasks - Array of tasks
 * @returns {Promise<Array<*>>} Promise of results array
 */
async function parallel(tasks) {
    return Promise.all(tasks.map(task => executeTask(task)));
}

// Module exports
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        // Core execution
        executeTask,
        attempt,
        sequence,
        parallel,

        // Task constructors
        succeed,
        fail,
        fromPromise,
        fromAsync,
        andThen,
        onError,
        map,

        // Constants (for testing)
        SUCCEED,
        FAIL,
        BINDING,
        AND_THEN,
        ON_ERROR,
        RECEIVE
    };
}

// Browser global
if (typeof window !== 'undefined') {
    window.CanopyTaskExecutor = module.exports;
}
