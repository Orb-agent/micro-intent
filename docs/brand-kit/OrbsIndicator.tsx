import { ThinkingOrb } from 'thinking-orbs';
import './orb-motion.css';
export type AppState = 'idle' | 'listening' | 'thinking' | 'acting' | 'confirmation' | 'done' | 'error';
const presets = {
 idle: {speed:.3,dotSize:.8}, listening: {speed:.65,dotSize:1},
 thinking: {speed:.75,dotSize:1}, acting: {speed:1.2,dotSize:1.15},
 confirmation: {speed:.3,dotSize:.8}, done: {speed:.3,dotSize:.8}, error: {speed:.3,dotSize:.8},
};
// Listening pulse matches the selected visual demo. It is not microphone-reactive.
// Supply reducedMotion from your app's prefers-reduced-motion hook.
// Include visible status text beside this decorative indicator.
export function OrbsIndicator({state, size=64, dark=false, reducedMotion=false}: {
 state: AppState; size?: 20 | 64; dark?: boolean; reducedMotion?: boolean;
}) {
 const paused=reducedMotion || ['confirmation','done','error'].includes(state);
 return <span className="orbs-motion" data-motion={state} data-paused={paused} aria-hidden="true"
   style={{width:size,height:size}}>
   <ThinkingOrb state="breathing" size={size} {...presets[state]}
     theme={dark ? 'dark' : 'light'} paused={paused}/>
 </span>;
}
