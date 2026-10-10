// Converts mic audio to 16 kHz mono PCM16 chunks of ~100 ms for Gemini Live.
class PcmWorklet extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunk = new Int16Array(1600);
    this.offset = 0;
  }

  process(inputs) {
    const channel = inputs[0] && inputs[0][0];
    if (!channel) return true;
    let peak = 0;
    for (let i = 0; i < channel.length; i++) {
      const s = Math.max(-1, Math.min(1, channel[i]));
      peak = Math.max(peak, Math.abs(s));
      this.chunk[this.offset++] = s < 0 ? s * 0x8000 : s * 0x7fff;
      if (this.offset === this.chunk.length) {
        this.port.postMessage({ pcm: this.chunk.buffer, peak }, [this.chunk.buffer]);
        this.chunk = new Int16Array(1600);
        this.offset = 0;
        peak = 0;
      }
    }
    return true;
  }
}

registerProcessor('pcm-worklet', PcmWorklet);
