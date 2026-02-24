/**
 * Simple gain processor worklet
 * Demonstrates AudioWorkletProcessor for custom audio processing
 */
class GainProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.gain = 1.0;

        // Listen for messages from main thread
        this.port.onmessage = (event) => {
            if (event.data.type === 'setGain') {
                this.gain = event.data.value;
            }
        };
    }

    /**
     * Process audio samples
     * @param {Float32Array[][]} inputs - Input audio samples
     * @param {Float32Array[][]} outputs - Output audio samples
     * @param {Object} parameters - Audio parameters
     * @returns {boolean} - Return true to keep processor alive
     */
    process(inputs, outputs, parameters) {
        const input = inputs[0];
        const output = outputs[0];

        // If no input, return silence
        if (!input || input.length === 0) {
            return true;
        }

        // Process each channel
        for (let channel = 0; channel < input.length; channel++) {
            const inputChannel = input[channel];
            const outputChannel = output[channel];

            // Apply gain to each sample
            for (let i = 0; i < inputChannel.length; i++) {
                outputChannel[i] = inputChannel[i] * this.gain;
            }
        }

        return true;
    }
}

// Register the processor
registerProcessor('gain-processor', GainProcessor);
