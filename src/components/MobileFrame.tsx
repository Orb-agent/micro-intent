import React from 'react';
import { Eye, ArrowRight, CheckCircle2 } from 'lucide-react';
import { CalendarWidget } from './widgets/CalendarWidget';
import { SbbTransitWidget } from './widgets/SbbTransitWidget';
import { AgentOrbs } from './AgentOrbs';
import { IntentState } from '../types';

interface MobileFrameProps {
  state: IntentState;
  onReviewChanges: () => void;
}

export const MobileFrame: React.FC<MobileFrameProps> = ({ state, onReviewChanges }) => {
  return (
    <div className="w-[340px] bg-black rounded-[48px] p-3 shadow-2xl border-4 border-gray-800 relative shrink-0 font-sans select-none">
      {/* iPhone Dynamic Island */}
      <div className="absolute top-5 left-1/2 -translate-x-1/2 w-28 h-6 bg-black rounded-full z-30 flex items-center justify-between px-3">
        <div className="w-2.5 h-2.5 rounded-full bg-gray-900"></div>
        <div className="w-2.5 h-2.5 rounded-full bg-indigo-950/80"></div>
      </div>

      {/* Phone Screen Container */}
      <div className="bg-white rounded-[38px] h-[680px] overflow-y-auto p-4 pt-10 flex flex-col justify-between relative no-scrollbar">
        
        {/* Mobile Header */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <span className="font-black text-lg text-gray-900 tracking-tight">luma</span>
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold text-gray-600">Zürich ⌄</span>
              <div className="w-6 h-6 rounded-full bg-emerald-100 text-emerald-700 font-bold text-[10px] flex items-center justify-center">
                🇨🇭
              </div>
            </div>
          </div>

          {/* Event Title Card */}
          <div className="mb-4">
            <h3 className="font-extrabold text-base text-gray-900">AI Hack Zürich</h3>
            <p className="text-xs text-gray-500 font-medium">{'{Tech: Europe} × Google DeepMind'}</p>
            
            <div className="flex items-center gap-2 mt-2">
              <span className="text-xs font-semibold text-gray-800 bg-gray-100 px-2 py-0.5 rounded-md">Sat, 10 Oct · 09:30</span>
              <span className="w-4 h-4 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center animate-pulse">
                <Eye className="w-2.5 h-2.5" />
              </span>
            </div>
          </div>

          {/* Widgets Stack */}
          <div className="space-y-3">
            <CalendarWidget 
              hasConflict={state.hasConflict}
              overlapMinutes={state.overlapMinutes}
              proposedShift={state.proposedShift}
              isConfirmed={state.isConfirmed}
            />

            <SbbTransitWidget 
              route={state.sbbRoute} 
              isConfirmed={state.isConfirmed}
            />
          </div>
        </div>

        {/* Mobile Agent Control Bar */}
        <div className="sticky bottom-0 bg-white/90 backdrop-blur-md pt-3 border-t border-gray-100 mt-4">
          <div className="flex items-center gap-2 mb-2">
            <AgentOrbs state={state.orbState} />
            <div className="flex-1 bg-gray-100 px-3 py-1.5 rounded-xl text-xs font-medium text-gray-700 truncate">
              {state.userQuery}
            </div>
          </div>

          {!state.isConfirmed ? (
            <button
              onClick={onReviewChanges}
              className="w-full bg-emerald-800 hover:bg-emerald-900 text-white py-3 rounded-2xl font-extrabold text-sm shadow-md flex items-center justify-center gap-2"
            >
              <span>Review plan</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          ) : (
            <div className="w-full bg-emerald-100 text-emerald-900 py-2.5 rounded-2xl font-bold text-xs flex items-center justify-center gap-1.5">
              <CheckCircle2 className="w-4 h-4 text-emerald-600" />
              <span>Confirmed & Ready</span>
            </div>
          )}
        </div>

      </div>
    </div>
  );
};
