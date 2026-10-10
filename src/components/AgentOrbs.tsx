import React from 'react';
import { OrbState } from '../types';

interface AgentOrbsProps {
  state: OrbState;
  onStateChange?: (state: OrbState) => void;
  showSelector?: boolean;
}

export const AgentOrbs: React.FC<AgentOrbsProps> = ({ state, onStateChange, showSelector = false }) => {
  return (
    <div className="flex flex-col items-center gap-3">
      {/* Orb Visualization */}
      <div className="relative flex items-center justify-center">
        {state === 'at_rest' && (
          <div className="w-10 h-10 rounded-full bg-gradient-to-tr from-sky-200 via-indigo-200 to-amber-100 shadow-lg shadow-sky-100 border border-white/80 flex items-center justify-center animate-pulse-slow">
            <div className="w-4 h-4 rounded-full bg-white/60 blur-[1px]"></div>
          </div>
        )}

        {state === 'listening' && (
          <div className="relative w-11 h-11 rounded-full bg-gradient-to-tr from-cyan-300 via-blue-400 to-indigo-300 shadow-xl shadow-cyan-200/50 flex items-center justify-center animate-pulse">
            <div className="absolute inset-0 rounded-full bg-cyan-400/30 animate-ping"></div>
            {/* Audio Wave lines */}
            <div className="flex items-center gap-0.5 z-10">
              <span className="w-0.5 h-3 bg-white rounded-full animate-bounce"></span>
              <span className="w-0.5 h-5 bg-white rounded-full animate-bounce [animation-delay:0.1s]"></span>
              <span className="w-0.5 h-2 bg-white rounded-full animate-bounce [animation-delay:0.2s]"></span>
              <span className="w-0.5 h-4 bg-white rounded-full animate-bounce [animation-delay:0.3s]"></span>
            </div>
          </div>
        )}

        {state === 'connecting' && (
          <div className="relative w-11 h-11 flex items-center justify-center">
            {/* Swirling orbiting nodes */}
            <div className="absolute w-12 h-12 rounded-full border-2 border-dashed border-cyan-400 animate-spin"></div>
            <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-indigo-400 via-purple-300 to-pink-300 shadow-lg shadow-purple-300/50 blur-[0.5px]"></div>
            <div className="absolute top-0 right-0 w-3 h-3 rounded-full bg-cyan-300 animate-ping"></div>
          </div>
        )}

        {state === 'ready' && (
          <div className="relative w-11 h-11 rounded-full bg-gradient-to-tr from-emerald-400 via-teal-300 to-cyan-300 shadow-lg shadow-emerald-200 flex items-center justify-center">
            <div className="w-5 h-5 rounded-full bg-white/70 shadow-inner"></div>
            <span className="absolute -top-0.5 -right-0.5 w-3.5 h-3.5 rounded-full bg-emerald-500 border-2 border-white flex items-center justify-center">
              <span className="w-1.5 h-1.5 rounded-full bg-white"></span>
            </span>
          </div>
        )}
      </div>

      {/* State Selector Demo Controls (Optional footer legend) */}
      {showSelector && (
        <div className="flex items-center gap-4 text-xs font-medium text-gray-500 bg-white/80 backdrop-blur px-4 py-2 rounded-full border border-gray-200/80 shadow-sm">
          <div className="flex items-center gap-1.5">
            <img 
              src="https://images.unsplash.com/photo-1564349683136-77e08dba1ef9?w=60&auto=format&fit=crop&q=80" 
              alt="Swiss Beaver Companion" 
              className="w-7 h-7 rounded-full object-cover border border-amber-300 shadow-sm" 
            />
            <span className="text-gray-700 font-semibold">Mascot</span>
          </div>
          <span className="text-gray-300">|</span>
          <button 
            onClick={() => onStateChange?.('at_rest')}
            className={`px-2 py-0.5 rounded-md transition ${state === 'at_rest' ? 'bg-gray-200 text-gray-900 font-bold' : 'hover:text-gray-700'}`}
          >
            At rest
          </button>
          <button 
            onClick={() => onStateChange?.('listening')}
            className={`px-2 py-0.5 rounded-md transition ${state === 'listening' ? 'bg-cyan-100 text-cyan-800 font-bold' : 'hover:text-gray-700'}`}
          >
            Listening
          </button>
          <button 
            onClick={() => onStateChange?.('connecting')}
            className={`px-2 py-0.5 rounded-md transition ${state === 'connecting' ? 'bg-purple-100 text-purple-800 font-bold' : 'hover:text-gray-700'}`}
          >
            Connecting
          </button>
          <button 
            onClick={() => onStateChange?.('ready')}
            className={`px-2 py-0.5 rounded-md transition ${state === 'ready' ? 'bg-emerald-100 text-emerald-800 font-bold' : 'hover:text-gray-700'}`}
          >
            Ready
          </button>
        </div>
      )}
    </div>
  );
};
