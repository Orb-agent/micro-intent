import React from 'react';
import { Monitor, Smartphone, Columns, Sparkles } from 'lucide-react';

interface HeaderBarProps {
  viewMode: 'desktop' | 'mobile' | 'split';
  onViewModeChange: (mode: 'desktop' | 'mobile' | 'split') => void;
}

export const HeaderBar: React.FC<HeaderBarProps> = ({ viewMode, onViewModeChange }) => {
  return (
    <header className="flex flex-col sm:flex-row items-center justify-between gap-3 mb-6">
      {/* Brand Title */}
      <div className="flex items-center gap-3">
        <div className="w-9 h-9 rounded-2xl bg-gradient-to-tr from-cyan-400 via-indigo-500 to-emerald-400 p-0.5 shadow-md">
          <div className="w-full h-full bg-white rounded-[14px] flex items-center justify-center">
            <span className="text-lg">🔮</span>
          </div>
        </div>
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-black tracking-tight text-gray-900">Micro Intent</h1>
            <span className="text-xs font-semibold text-gray-500">From discovery to action.</span>
          </div>
          <p className="text-xs font-medium text-emerald-700 flex items-center gap-1">
            <Sparkles className="w-3 h-3 text-emerald-500" />
            <span>Agentic AI Hack Zürich · Google DeepMind</span>
          </p>
        </div>
      </div>

      {/* View Mode Controls */}
      <div className="flex items-center gap-1.5 bg-white p-1 rounded-2xl border border-gray-200 shadow-sm text-xs font-bold text-gray-600">
        <button
          onClick={() => onViewModeChange('desktop')}
          className={`px-3 py-1.5 rounded-xl flex items-center gap-1.5 transition ${
            viewMode === 'desktop' ? 'bg-gray-900 text-white shadow-xs' : 'hover:text-gray-900'
          }`}
        >
          <Monitor className="w-3.5 h-3.5" />
          <span>Desktop</span>
        </button>

        <button
          onClick={() => onViewModeChange('split')}
          className={`px-3 py-1.5 rounded-xl flex items-center gap-1.5 transition ${
            viewMode === 'split' ? 'bg-gray-900 text-white shadow-xs' : 'hover:text-gray-900'
          }`}
        >
          <Columns className="w-3.5 h-3.5" />
          <span>Split Demo</span>
        </button>

        <button
          onClick={() => onViewModeChange('mobile')}
          className={`px-3 py-1.5 rounded-xl flex items-center gap-1.5 transition ${
            viewMode === 'mobile' ? 'bg-gray-900 text-white shadow-xs' : 'hover:text-gray-900'
          }`}
        >
          <Smartphone className="w-3.5 h-3.5" />
          <span>Mobile</span>
        </button>
      </div>
    </header>
  );
};
