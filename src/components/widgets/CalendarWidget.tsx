import React from 'react';
import { Calendar, ArrowLeft, Clock, AlertTriangle } from 'lucide-react';

interface CalendarWidgetProps {
  hasConflict: boolean;
  overlapMinutes: number;
  proposedShift: {
    originalSlot: string;
    newSlot: string;
    title: string;
  };
  isConfirmed?: boolean;
}

export const CalendarWidget: React.FC<CalendarWidgetProps> = ({
  hasConflict,
  overlapMinutes,
  proposedShift,
  isConfirmed = false
}) => {
  return (
    <div className="bg-white/95 backdrop-blur-md rounded-2xl p-4 border border-gray-200/80 shadow-md transition-all hover:shadow-lg">
      {/* Top Bar / Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {/* Google Calendar Icon */}
          <div className="w-6 h-6 rounded bg-white shadow-sm border border-gray-200 flex items-center justify-center">
            <span className="text-xs font-bold text-blue-600">31</span>
          </div>
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Google Calendar</span>
          <span className="text-xs text-gray-300">•</span>
          {!isConfirmed ? (
            <span className="inline-flex items-center gap-1 text-sm font-bold text-amber-600 bg-amber-50 px-2 py-0.5 rounded-md border border-amber-200">
              <AlertTriangle className="w-3.5 h-3.5 text-amber-500" />
              {overlapMinutes} min overlap
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 text-xs font-bold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-md border border-emerald-200">
              ✓ Resolved & Scheduled
            </span>
          )}
        </div>

        {!isConfirmed && (
          <div className="flex items-center gap-1.5 bg-amber-50 border border-amber-200 px-3 py-1.5 rounded-xl text-xs font-medium text-amber-900 shadow-sm">
            <Clock className="w-3.5 h-3.5 text-amber-600" />
            <span>Move focus to <strong>{proposedShift.newSlot}</strong></span>
            <span className="ml-1 text-[10px] bg-amber-200/80 text-amber-900 px-1.5 py-0.5 rounded font-semibold">Proposed change</span>
          </div>
        )}
      </div>

      {/* Visual Timeline Diagram */}
      <div className="relative mt-2 pt-2 border-t border-gray-100">
        {/* Time ticks */}
        <div className="grid grid-cols-5 text-[11px] font-mono text-gray-400 mb-2">
          <span>08:00</span>
          <span>08:30</span>
          <span>09:00</span>
          <span>09:30</span>
          <span>10:00</span>
        </div>

        {/* Timeline Track & Slots */}
        <div className="relative h-20 bg-gray-50 rounded-xl p-2 border border-gray-100 flex items-center gap-2 overflow-hidden">
          
          {/* Slot 1: Proposed shift 08:00 - 08:30 */}
          <div className={`flex-1 h-14 rounded-lg p-2 flex flex-col justify-between transition-all ${
            isConfirmed 
              ? 'bg-emerald-100 border-2 border-emerald-500 shadow-sm' 
              : 'bg-blue-50/70 border-2 border-dashed border-blue-400'
          }`}>
            <span className="text-[10px] font-bold text-blue-700 uppercase tracking-tight">Proposed</span>
            <span className="text-xs font-semibold text-blue-900">{proposedShift.newSlot}</span>
          </div>

          {/* Curved Arrow / Flow connector */}
          {!isConfirmed && (
            <div className="flex items-center justify-center px-1 text-blue-400">
              <ArrowLeft className="w-5 h-5 animate-pulse" />
            </div>
          )}

          {/* Slot 2: Original Focus time 09:15 - 09:45 */}
          {!isConfirmed ? (
            <div className="w-36 h-14 bg-amber-100/90 border border-amber-300 rounded-lg p-2 relative overflow-hidden flex flex-col justify-between">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold text-amber-800">Focus time</span>
                <span className="text-[9px] font-mono text-amber-700">09:15 - 09:45</span>
              </div>
              
              {/* Overlap Striped Texture for 09:30-09:45 */}
              <div className="absolute right-0 top-0 bottom-0 w-1/2 bg-[repeating-linear-gradient(45deg,#f59e0b,#f59e0b_6px,#fbbf24_6px,#fbbf24_12px)] opacity-30"></div>
              
              <div className="text-[10px] font-semibold text-amber-900 z-10 flex items-center gap-1">
                <span>15 min overlap</span>
              </div>
            </div>
          ) : (
            <div className="w-24 h-14 bg-gray-100 border border-gray-200 rounded-lg p-2 opacity-50 line-through text-[10px] text-gray-400">
              Original slot (Moved)
            </div>
          )}

          {/* Slot 3: Agentic AI Hack Zürich 09:30 - 12:00 */}
          <div className="flex-1 h-14 bg-emerald-100/80 border border-emerald-300 rounded-lg p-2 flex flex-col justify-between">
            <span className="text-[10px] font-bold text-emerald-800">AI Hack</span>
            <span className="text-xs font-semibold text-emerald-900">09:30 - 12:00</span>
          </div>
        </div>

        {/* Sub-label under overlap */}
        {!isConfirmed && (
          <div className="flex justify-end text-[11px] font-medium text-amber-600 mt-1 mr-24">
            <span>↓ 15 min overlap</span>
          </div>
        )}
      </div>
    </div>
  );
};
