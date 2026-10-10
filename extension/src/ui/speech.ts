// Reads answers aloud with the browser's voice; no network needed.
let speaking = false;

export function speak(text: string, lang: string, large: boolean): Promise<void> {
  stopSpeaking();
  if (!text || !('speechSynthesis' in window)) return Promise.resolve();
  return new Promise((resolve) => {
    const u = new SpeechSynthesisUtterance(text);
    u.lang = lang === 'de' ? 'de-CH' : 'en-GB';
    u.rate = large ? 0.92 : 1.04;
    u.onend = u.onerror = () => {
      speaking = false;
      resolve();
    };
    speaking = true;
    speechSynthesis.speak(u);
  });
}

export function stopSpeaking() {
  if (speaking && 'speechSynthesis' in window) speechSynthesis.cancel();
  speaking = false;
}
