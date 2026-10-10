import React, { useState, useEffect } from 'react';
import { Mic, MicOff, Eye, ArrowRight, Sparkles, Volume2 } from 'lucide-react';
import { AgentOrbs } from './AgentOrbs';
import { OrbState } from '../types';

interface AgentControlBarProps {
  orbState: OrbState;
  onOrbStateChange: (state: OrbState) => void;
  userQuery: string;
  onQueryChange: (query: string) => void;
  isGazeActive: boolean;
  onGazeToggle: () => void;
  onReviewChanges: () => void;
  isConfirmed?: boolean;
}

export const AgentControlBar: React.FC<AgentControlBarProps> = ({
  orbState,
  onOrbStateChange,
  userQuery,
  onQueryChange,
  isGazeActive,
  onGazeToggle,
  onReviewChanges,
  isConfirmed = false
}) => {
  const [isListening, setIsListening] = useState(false);
  const [speechRecognition, setSpeechRecognition] = useState<any>(null);

  useEffect(() => {
    // Check Web Speech API availability
    if (typeof window !== 'undefined' && ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window)) {
      const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
      const recognition = new SpeechRecognition();
      recognition.continuous = false;
      recognition.interimResults = true;
      recognition.lang = 'en-US';

      recognition.onstart = () => {
        setIsListening(true);
        onOrbStateChange('listening');
      };

      recognition.onresult = (event: any) => {
        const transcript = Array.from(event.results)
          .map((result: any) => result[0])
          .map((result) => result.transcript)
          .join('');
        onQueryChange(transcript);
      };

      recognition.onend = () => {
        setIsListening(false);
        onOrbStateChange('ready');
      };

      setSpeechRecognition(recognition);
    }
  }, []);

  const toggleListen = () => {
    if (isListening) {
      speechRecognition?.stop();
      setIsListening(false);
      onOrbStateChange('ready');
    } else {
      if (speechRecognition) {
        try {
          speechRecognition.start();
        } catch (e) {
          console.warn("Speech recognition error:", e);
        }
      } else {
        // Fallback simulation if browser speech API is restricted
        setIsListening(true);
        onOrbStateChange('listening');
        setTimeout(() => {
          setIsListening(false);
          onOrbStateChange('ready');
        }, 3000);
      }
    }
  };

  return (
    <div className="bg-white/95 backdrop-blur-xl rounded-3xl p-3 border border-gray-200/90 shadow-2xl flex flex-col md:flex-row items-center justify-between gap-4 transition-all">
      
      {/* Left: Orb & Voice Waveform Transcript */}
      <div className="flex items-center gap-3 w-full md:w-auto flex-1">
        <AgentOrbs state={orbState} onStateChange={onOrbStateChange} />

        {/* Text Transcript & Audio Visualizer */}
        <div className="flex-1 min-w-0 bg-gray-50/80 px-4 py-2.5 rounded-2xl border border-gray-200/60 flex items-center justify-between gap-2">
          <input
            type="text"
            value={userQuery}
            onChange={(e) => onQueryChange(e.target.value)}
            placeholder="Speak or type your intent..."
            className="w-full bg-transparent text-sm font-medium text-gray-900 focus:outline-none placeholder:text-gray-400"
          />
          {isListening && (
            <div className="flex items-center gap-1">
              <span className="w-1 h-4 bg-cyan-500 rounded-full animate-pulse"></span>
              <span className="w-1 h-6 bg-cyan-600 rounded-full animate-pulse [animation-delay:0.15s]"></span>
              <span className="w-1 h-3 bg-cyan-400 rounded-full animate-pulse [animation-delay:0.3s]"></span>
            </div>
          )}
        </div>
      </div>

      {/* Right Controls: Mic, Gaze Toggle, Human Checkpoint Action Button */}
      <div className="flex items-center gap-3 w-full md:w-auto justify-end">
        
        {/* Mic Toggle Button */}
        <button
          onClick={toggleListen}
          className={`p-2.5 rounded-2xl border transition-all flex items-center justify-center ${
            isListening
              ? 'bg-red-50 text-red-600 border-red-300 animate-pulse shadow-md'
              : 'bg-gray-100 text-gray-700 border-gray-200 hover:bg-gray-200'
          }`}
          title="Toggle Voice Input"
        >
          {isListening ? <MicOff className="w-4 h-4" /> : <Mic className="w-4 h-4" />}
        </button>

        {/* Gaze Toggle Button */}
        <button
          onClick={onGazeToggle}
          className={`px-3 py-2.5 rounded-2xl border text-xs font-semibold flex items-center gap-1.5 transition-all ${
            isGazeActive
              ? 'bg-blue-50 text-blue-700 border-blue-300 shadow-sm'
              : 'bg-gray-100 text-gray-600 border-gray-200 hover:bg-gray-200'
          }`}
        >
          <Eye className={`w-4 h-4 ${isGazeActive ? 'text-blue-600 animate-pulse' : 'text-gray-400'}`} />
          <span>{isGazeActive ? 'Gaze on' : 'Gaze off'}</span>
        </button>

        {/* Human Checkpoint Action Button */}
        {!isConfirmed ? (
          <button
            onClick={onReviewChanges}
            className="group relative bg-gradient-to-r from-emerald-800 via-emerald-700 to-teal-800 hover:from-emerald-900 hover:to-teal-900 text-white px-5 py-2.5 rounded-2xl font-bold shadow-lg hover:shadow-xl transition-all flex flex-col items-start min-w-[200px]"
          >
            <div className="flex items-center justify-between w-full">
              <span className="text-sm tracking-tight flex items-center gap-1.5">
                Review 2 changes
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </span>
            </div>
            <span className="text-[10px] font-normal text-emerald-200/90 tracking-tight">
              Move focus time + add event · Awaiting your confirmation
            </span>
          </button>
        ) : (
          <div className="bg-emerald-100 text-emerald-900 border border-emerald-300 px-5 py-2.5 rounded-2xl font-bold text-xs flex items-center gap-2 shadow-sm">
            <Sparkles className="w-4 h-4 text-emerald-600" />
            <span>Actions Approved & Saved!</span>
          </div>
        )}
      </div>
    </div>
  );
};
