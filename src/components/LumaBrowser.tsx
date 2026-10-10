import React from 'react';
import { Search, Plus, Share2, Eye, MapPin, Calendar as CalendarIcon, Clock, ChevronDown, CheckCircle } from 'lucide-react';
import { CalendarWidget } from './widgets/CalendarWidget';
import { SbbTransitWidget } from './widgets/SbbTransitWidget';
import { AgentControlBar } from './AgentControlBar';
import { IntentState, OrbState } from '../types';

interface LumaBrowserProps {
  state: IntentState;
  onOrbStateChange: (state: OrbState) => void;
  onQueryChange: (query: string) => void;
  onGazeToggle: () => void;
  onReviewChanges: () => void;
  onSelectEvent?: (eventTitle: string) => void;
}

export const LumaBrowser: React.FC<LumaBrowserProps> = ({
  state,
  onOrbStateChange,
  onQueryChange,
  onGazeToggle,
  onReviewChanges,
  onSelectEvent
}) => {
  return (
    <div className="bg-white rounded-3xl shadow-2xl border border-gray-200/80 overflow-hidden flex-1 flex flex-col font-sans">
      
      {/* macOS Browser Chrome Bar */}
      <div className="bg-gray-100/90 backdrop-blur border-b border-gray-200 px-4 py-2.5 flex items-center justify-between">
        {/* Window controls */}
        <div className="flex items-center gap-2">
          <span className="w-3 h-3 rounded-full bg-red-400 border border-red-500 inline-block"></span>
          <span className="w-3 h-3 rounded-full bg-amber-400 border border-amber-500 inline-block"></span>
          <span className="w-3 h-3 rounded-full bg-emerald-400 border border-emerald-500 inline-block"></span>
        </div>

        {/* Address Bar */}
        <div className="flex-1 max-w-md mx-4 bg-white rounded-lg px-3 py-1 border border-gray-200 shadow-2xs text-xs font-mono text-gray-600 flex items-center gap-2">
          <span className="text-gray-400">🔒</span>
          <span>luma.com/zurich</span>
        </div>

        {/* Action icons */}
        <div className="flex items-center gap-3 text-gray-400">
          <Share2 className="w-3.5 h-3.5 hover:text-gray-600 cursor-pointer" />
          <span className="text-xs font-semibold text-gray-400">⌘+L</span>
        </div>
      </div>

      {/* Luma Navigation Header */}
      <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="font-black text-2xl text-gray-900 tracking-tight">luma</span>
          <nav className="flex items-center gap-4 text-sm font-medium text-gray-600">
            <span className="text-gray-900 font-semibold cursor-pointer">Discover</span>
            <div className="flex items-center gap-1 cursor-pointer hover:text-gray-900">
              <span>Zürich</span>
              <ChevronDown className="w-3.5 h-3.5" />
            </div>
          </nav>
        </div>

        <div className="flex items-center gap-4">
          <div className="relative">
            <Search className="w-4 h-4 text-gray-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input 
              type="text" 
              placeholder="Search events..." 
              className="bg-gray-100 rounded-full pl-9 pr-4 py-1.5 text-xs text-gray-700 focus:outline-none w-44"
            />
          </div>
          <button className="bg-gray-100 hover:bg-gray-200 text-gray-800 text-xs font-bold px-3.5 py-1.5 rounded-full flex items-center gap-1.5 transition">
            <Plus className="w-3.5 h-3.5" />
            <span>Submit Event</span>
          </button>
          <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-800 font-bold text-xs flex items-center justify-center border border-emerald-200">
            🇨🇭
          </div>
          <img 
            src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=80&auto=format&fit=crop&q=80" 
            alt="User avatar" 
            className="w-8 h-8 rounded-full object-cover border border-gray-200"
          />
        </div>
      </div>

      {/* Main Content Area: Left Event Feed + Right Event Detail */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-0 overflow-y-auto">
        
        {/* Left Events Sidebar (4 Cols) */}
        <div className="lg:col-span-4 border-r border-gray-100 p-5 bg-gray-50/50">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-bold text-gray-900">Events</h2>
            <div className="flex items-center gap-2 text-xs font-semibold text-gray-500">
              <span className="text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-md font-bold">Today</span>
              <span className="hover:text-gray-900 cursor-pointer">This Week</span>
              <span className="hover:text-gray-900 cursor-pointer">This Month</span>
            </div>
          </div>

          {/* Timeline Event List */}
          <div className="space-y-4 relative">
            {/* Timeline Vertical Line */}
            <div className="absolute left-3 top-3 bottom-3 w-0.5 bg-gray-200"></div>

            {/* Event Item 1: 9:00 AM */}
            <div className="relative pl-8 flex items-start gap-3 opacity-60">
              <div className="absolute left-1.5 top-1.5 w-3 h-3 rounded-full bg-gray-300 border-2 border-white"></div>
              <div>
                <span className="text-[11px] font-mono font-bold text-gray-500">9:00 AM</span>
                <h4 className="text-xs font-bold text-gray-900">From the Ground up: Robotics Essentials</h4>
                <p className="text-[10px] text-gray-500">ETH Robotics Club</p>
              </div>
            </div>

            {/* Event Item 2: 9:30 AM (ACTIVE / HIGHLIGHTED) */}
            <div 
              onClick={() => onSelectEvent?.('Agentic AI Hack Zürich')}
              className="relative pl-8 flex items-start gap-3 bg-white p-3 rounded-2xl border-2 border-emerald-500 shadow-md cursor-pointer transition transform hover:-translate-y-0.5"
            >
              <div className="absolute left-1.5 top-4 w-3.5 h-3.5 rounded-full bg-emerald-500 border-2 border-white animate-pulse"></div>
              <div className="flex-1">
                <span className="text-xs font-mono font-bold text-emerald-700">9:30 AM</span>
                <h4 className="text-sm font-extrabold text-gray-900">Agentic AI Hack Zürich</h4>
                <p className="text-xs font-medium text-emerald-800">{'{Tech: Europe} × Google DeepMind'}</p>
              </div>
              <img 
                src="https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=120&auto=format&fit=crop&q=80" 
                alt="Swiss Alps banner"
                className="w-12 h-12 rounded-xl object-cover border border-emerald-200 shadow-2xs"
              />
            </div>

            {/* Event Item 3: 2:30 PM */}
            <div className="relative pl-8 flex items-start gap-3 opacity-70">
              <div className="absolute left-1.5 top-1.5 w-3 h-3 rounded-full bg-gray-300 border-2 border-white"></div>
              <div>
                <span className="text-[11px] font-mono font-bold text-gray-500">2:30 PM</span>
                <h4 className="text-xs font-bold text-gray-900">Sip & Pumpkin Carve</h4>
                <p className="text-[10px] text-gray-500">Oubytori Community</p>
              </div>
            </div>

            {/* Event Item 4: 5:00 PM */}
            <div className="relative pl-8 flex items-start gap-3 opacity-70">
              <div className="absolute left-1.5 top-1.5 w-3 h-3 rounded-full bg-gray-300 border-2 border-white"></div>
              <div>
                <span className="text-[11px] font-mono font-bold text-gray-500">5:00 PM</span>
                <h4 className="text-xs font-bold text-gray-900">Turn Down the Noise</h4>
                <p className="text-[10px] text-gray-500">UNICEF x Global Youth Mental Health</p>
              </div>
            </div>

            {/* Event Item 5: 7:00 PM */}
            <div className="relative pl-8 flex items-start gap-3 opacity-70">
              <div className="absolute left-1.5 top-1.5 w-3 h-3 rounded-full bg-gray-300 border-2 border-white"></div>
              <div>
                <span className="text-[11px] font-mono font-bold text-gray-500">7:00 PM</span>
                <h4 className="text-xs font-bold text-gray-900">Zürich Founders Dinner</h4>
              </div>
            </div>
          </div>
        </div>

        {/* Right Detail View (8 Cols) */}
        <div className="lg:col-span-8 p-6 flex flex-col justify-between bg-white relative">
          <div>
            {/* Header Banner Split */}
            <div className="flex flex-col md:flex-row items-start justify-between gap-4 mb-6">
              <div>
                <h1 className="text-3xl font-black text-gray-900 tracking-tight mb-1">
                  Agentic AI Hack Zürich
                </h1>
                <p className="text-base font-semibold text-emerald-800 mb-3">
                  {'{Tech: Europe} × Google DeepMind'}
                </p>

                {/* Date & Location Badges */}
                <div className="flex flex-wrap items-center gap-3">
                  <div className="flex items-center gap-2 bg-blue-50 border border-blue-200 px-3 py-1.5 rounded-xl text-xs font-bold text-blue-900">
                    <CalendarIcon className="w-4 h-4 text-blue-600" />
                    <span>Sat, 10 Oct · 09:30</span>
                    {state.isGazeActive && (
                      <span className="flex items-center gap-1 bg-blue-500 text-white text-[10px] px-2 py-0.5 rounded-full font-bold animate-pulse">
                        <Eye className="w-3 h-3" />
                        Context: this event
                      </span>
                    )}
                  </div>

                  <div className="flex items-center gap-1.5 text-xs font-semibold text-gray-600 bg-gray-100 px-3 py-1.5 rounded-xl">
                    <MapPin className="w-4 h-4 text-red-500" />
                    <span>Josefstrasse 206, Zürich</span>
                  </div>
                </div>
              </div>

              {/* Event Hero Banner Image */}
              <div className="w-full md:w-56 h-36 rounded-2xl overflow-hidden shadow-lg border border-gray-200 relative group shrink-0">
                <img 
                  src="https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=600&auto=format&fit=crop&q=80" 
                  alt="Swiss Alps banner"
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-gray-950/80 via-transparent to-transparent flex flex-col justify-end p-3 text-white">
                  <span className="text-[10px] font-black tracking-widest text-emerald-400 uppercase">AGENTIC AI HACK</span>
                  <span className="text-xs font-extrabold">ZÜRICH · 10 OCT 2026</span>
                </div>
              </div>
            </div>

            {/* Dynamic Ephemeral Widgets Container */}
            <div className="space-y-4 mb-6">
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

          {/* Bottom Floating Agent Control Bar */}
          <div className="mt-4">
            <AgentControlBar 
              orbState={state.orbState}
              onOrbStateChange={onOrbStateChange}
              userQuery={state.userQuery}
              onQueryChange={onQueryChange}
              isGazeActive={state.isGazeActive}
              onGazeToggle={onGazeToggle}
              onReviewChanges={onReviewChanges}
              isConfirmed={state.isConfirmed}
            />
          </div>

        </div>

      </div>
    </div>
  );
};
