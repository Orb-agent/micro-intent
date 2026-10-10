import { Check } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { ThinkingOrb, type OrbState as ThinkingState } from 'thinking-orbs';

export type OrbState = 'idle' | 'listening' | 'thinking' | 'searching' | 'speaking' | 'done';

const MODE: Record<OrbState, ThinkingState> = {
  idle: 'breathing',
  listening: 'listening',
  thinking: 'solving',
  searching: 'searching',
  speaking: 'composing',
  done: 'breathing',
};

const TINT: Partial<Record<OrbState, string>> = {
  listening: '#8fb4ff',
  done: '#6ee7a8',
};

/** The assistant's face, drawn by thinking-orbs; grows with the mic level while listening. */
export function Orb({ state, level = 0, size }: { state: OrbState; level?: number; size: number }) {
  return (
    <motion.span
      className="mi-orb"
      data-state={state}
      style={{ width: size, height: size }}
      animate={{ scale: state === 'listening' ? 1 + level * 0.25 : 1 }}
      transition={{ type: 'spring', stiffness: 500, damping: 24 }}
    >
      <ThinkingOrb
        state={MODE[state]}
        size={size >= 40 ? 64 : 32}
        theme="dark"
        color={TINT[state]}
        style={{ width: size, height: size }}
        aria-label={state}
      />
      <AnimatePresence>
        {state === 'done' && (
          <motion.span
            className="mi-orb-check"
            initial={{ scale: 0.3, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.3, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 520, damping: 18 }}
          >
            <Check size={size * 0.42} strokeWidth={3.2} />
          </motion.span>
        )}
      </AnimatePresence>
    </motion.span>
  );
}
