"use strict";

class Pcm extends AudioWorkletProcessor {
  constructor() {
    super();
    this.buf = new Int16Array(1920);
    this.n = 0;
  }

  process(inputs) {
    const channel = inputs[0][0];
    if (!channel) return true;
    for (let i = 0; i < channel.length; i++) {
      const sample = Math.max(-1, Math.min(1, channel[i]));
      this.buf[this.n++] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
      if (this.n === this.buf.length) {
        this.port.postMessage(this.buf.buffer, [this.buf.buffer]);
        this.buf = new Int16Array(1920);
        this.n = 0;
      }
    }
    return true;
  }
}

registerProcessor("pcm", Pcm);
