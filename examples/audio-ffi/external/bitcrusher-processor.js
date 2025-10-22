/**
 * Bitcrusher audio processor worklet
 * Demonstrates more advanced AudioWorkletProcessor with bidirectional communication
 *
 * This processor reduces bit depth and sample rate for a lo-fi distortion effect
 */
class BitcrusherProcessor extends AudioWorkletProcessor {
    constructor() {
        super();

        // Initial parameters
        this.bitDepth = 8;           // bits (1-16)
        this.sampleRateReduction = 1; // factor (1-10)
        this.lastSample = 0;
        this.sampleCounter = 0;

        // Listen for parameter changes from main thread
        this.port.onmessage = (event) => {
            const { type, value } = event.data;

            switch (type) {
                case 'setBitDepth':
                    this.bitDepth = Math.max(1, Math.min(16, value));
                    this.sendStatus();
                    break;

                case 'setSampleRateReduction':
                    this.sampleRateReduction = Math.max(1, Math.min(10, value));
                    this.sendStatus();
                    break;

                case 'getStatus':
                    this.sendStatus();
                    break;

                case 'reset':
                    this.lastSample = 0;
                    this.sampleCounter = 0;
                    this.sendStatus();
                    break;
            }
        };

        // Send initial status
        this.sendStatus();
    }

    /**
     * Send current processor status back to main thread
     */
    sendStatus() {
        this.port.postMessage({
            type: 'status',
            bitDepth: this.bitDepth,
            sampleRateReduction: this.sampleRateReduction
        });
    }

    /**
     * Process audio samples with bitcrushing effect
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

            for (let i = 0; i < inputChannel.length; i++) {
                // Sample rate reduction: hold the same value for multiple samples
                if (this.sampleCounter % this.sampleRateReduction === 0) {
                    // Bit depth reduction
                    const sample = inputChannel[i];
                    const levels = Math.pow(2, this.bitDepth);
                    const step = 2 / levels;

                    // Quantize the sample to reduced bit depth
                    this.lastSample = Math.floor((sample + 1) / step) * step - 1;
                    this.lastSample = Math.max(-1, Math.min(1, this.lastSample));
                }

                outputChannel[i] = this.lastSample;
                this.sampleCounter++;
            }
        }

        return true;
    }
}

// Register the processor
registerProcessor('bitcrusher-processor', BitcrusherProcessor);
