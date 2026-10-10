import React from 'react';
import { Train, Navigation, MapPin, CheckCircle2 } from 'lucide-react';
import { SbbRouteData } from '../../types';

interface SbbTransitWidgetProps {
  route: SbbRouteData | null;
  isConfirmed?: boolean;
}

export const SbbTransitWidget: React.FC<SbbTransitWidgetProps> = ({ route, isConfirmed = false }) => {
  // Fallback defaults if route is loading or null
  const departureTime = route?.departureTime || '08:42';
  const arrivalTime = route?.arrivalTime || '09:07';
  const venueArrival = '09:19';
  const fromCity = route?.from || 'Winterthur';
  const onwardMinutes = route?.onwardJourneyMinutes || 12;
  const notice = route?.arrivalNotice || 'Arrive 11 min before start';

  return (
    <div className="bg-white/95 backdrop-blur-md rounded-2xl p-4 border border-gray-200/80 shadow-md transition-all hover:shadow-lg">
      {/* Top Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {/* SBB Logo Badge */}
          <div className="bg-[#EB0000] text-white px-2 py-0.5 rounded font-black text-xs tracking-tighter flex items-center gap-1 shadow-sm">
            <span>SBB</span>
            <span className="text-[10px] font-mono">FFS</span>
          </div>
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider">+ Maps</span>
        </div>

        {/* Arrival Badge */}
        <div className="flex items-center gap-1.5 bg-emerald-50 border border-emerald-200 px-3 py-1 rounded-xl text-xs font-bold text-emerald-800 shadow-sm">
          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
          <span>{notice}</span>
        </div>
      </div>

      {/* Route Node Diagram & Map split */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-center mt-2 pt-2 border-t border-gray-100">
        
        {/* Node Flow Diagram (Cols 1-3) */}
        <div className="md:col-span-3 relative py-2">
          <div className="flex items-center justify-between relative z-10">
            
            {/* Origin Node */}
            <div className="flex flex-col items-start">
              <span className="text-xs font-bold text-gray-900">{fromCity}</span>
              <span className="text-sm font-extrabold text-gray-700 font-mono">{departureTime}</span>
            </div>

            {/* SBB Train Segment */}
            <div className="flex-1 px-4 relative flex flex-col items-center">
              {/* Connecting Red Line */}
              <div className="w-full h-1 bg-red-600 rounded-full relative flex items-center justify-center">
                {/* Train Icon Floating in Center */}
                <div className="w-6 h-6 rounded-full bg-red-600 text-white flex items-center justify-center shadow-md -mt-0.5 border border-white">
                  <Train className="w-3.5 h-3.5" />
                </div>
              </div>
            </div>

            {/* Transfer Node (Zürich HB) */}
            <div className="flex flex-col items-center">
              <span className="text-xs font-bold text-gray-900">Zürich HB</span>
              <span className="text-sm font-extrabold text-gray-700 font-mono">{arrivalTime}</span>
            </div>

            {/* Onward Walk Segment */}
            <div className="flex-1 px-4 relative flex flex-col items-center">
              {/* Dotted Line */}
              <div className="w-full border-t-2 border-dashed border-gray-400 relative flex items-center justify-center">
                <span className="text-[10px] font-semibold text-gray-500 bg-white px-2 py-0.5 -mt-3 rounded-full border border-gray-200 shadow-2xs">
                  {onwardMinutes} min onward journey
                </span>
              </div>
            </div>

            {/* Final Destination Node (Venue) */}
            <div className="flex flex-col items-end">
              <span className="text-xs font-bold text-emerald-800 flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5 text-emerald-600 fill-emerald-100" />
                Venue
              </span>
              <span className="text-sm font-extrabold text-emerald-900 font-mono">{venueArrival}</span>
            </div>

          </div>
        </div>

        {/* Mini Interactive Map Thumbnail (Col 4) */}
        <div className="relative h-20 rounded-xl overflow-hidden border border-gray-200 shadow-inner group">
          <img 
            src="https://images.unsplash.com/photo-1527631746610-bca00a040d60?w=300&auto=format&fit=crop&q=80" 
            alt="Zürich Map"
            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-gray-900/60 via-transparent to-transparent flex items-end p-2">
            <div className="flex items-center gap-1 text-[11px] font-bold text-white">
              <Navigation className="w-3 h-3 text-red-500 fill-red-500 animate-pulse" />
              <span>Zürich HB → Josefstrasse</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
};
