import { useCallback, useEffect, useRef, useState } from 'react';

export type ReadAloudStatus = 'idle' | 'speaking';

function getSpeechSynthesis(): SpeechSynthesis | null {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return null;
  return window.speechSynthesis;
}

function getEnglishVoice(voices: SpeechSynthesisVoice[]): SpeechSynthesisVoice | null {
  const englishVoices = voices.filter((voice) => /^en(?:-|_)/i.test(voice.lang));
  return englishVoices.find((voice) => /^en-US(?:-|$)/i.test(voice.lang)) ?? englishVoices[0] ?? null;
}

export function useReadAloud() {
  const [status, setStatus] = useState<ReadAloudStatus>('idle');
  const [supported, setSupported] = useState(false);
  const [error, setError] = useState('');
  const synthesisRef = useRef<SpeechSynthesis | null>(null);
  const voicesRef = useRef<SpeechSynthesisVoice[]>([]);
  const generationRef = useRef(0);

  const stop = useCallback(() => {
    generationRef.current += 1;
    try {
      (synthesisRef.current ?? getSpeechSynthesis())?.cancel();
    } catch {
      // Reset the UI even if the browser's speech engine has already stopped.
    }
    setStatus('idle');
    setError('');
  }, []);

  const speak = useCallback((text: string) => {
    const synthesis = synthesisRef.current ?? getSpeechSynthesis();
    if (!synthesis || typeof SpeechSynthesisUtterance === 'undefined') {
      setSupported(false);
      setError('Read-aloud is not supported in this browser.');
      setStatus('idle');
      return;
    }

    const cleanText = text.trim();
    if (!cleanText) {
      setError('There is no text to read aloud.');
      setStatus('idle');
      return;
    }

    const generation = ++generationRef.current;
    synthesis.cancel();
    setSupported(true);
    setError('');
    setStatus('speaking');

    const utterance = new SpeechSynthesisUtterance(cleanText);
    const englishVoice = getEnglishVoice(synthesis.getVoices() ?? voicesRef.current);
    // If the browser has no English voice installed, en-US asks its default
    // speech engine for English pronunciation rather than choosing another locale.
    utterance.lang = englishVoice?.lang || 'en-US';
    if (englishVoice) utterance.voice = englishVoice;

    utterance.onend = () => {
      if (generation !== generationRef.current) return;
      setStatus('idle');
    };
    utterance.onerror = (event) => {
      if (generation !== generationRef.current) return;
      setStatus('idle');
      if (event.error !== 'canceled' && event.error !== 'interrupted') {
        setError(`Read-aloud failed: ${event.error || 'speech could not be played.'}`);
      }
    };

    try {
      synthesis.speak(utterance);
    } catch (cause) {
      if (generation !== generationRef.current) return;
      setStatus('idle');
      setError(cause instanceof Error ? cause.message : 'Read-aloud could not be started.');
    }
  }, []);

  useEffect(() => {
    const synthesis = getSpeechSynthesis();
    if (!synthesis) return;

    synthesisRef.current = synthesis;
    setSupported(true);
    voicesRef.current = synthesis.getVoices();

    const updateVoices = () => {
      voicesRef.current = synthesis.getVoices();
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'hidden') stop();
    };

    synthesis.addEventListener('voiceschanged', updateVoices);
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      generationRef.current += 1;
      synthesis.removeEventListener('voiceschanged', updateVoices);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      synthesis.cancel();
      synthesisRef.current = null;
    };
  }, [stop]);

  return { status, speaking: status === 'speaking', supported, speak, stop, error };
}
