import React, { useState } from 'react';
import { Check, X, ShieldAlert, Calendar, Train, ArrowRight, Sparkles, CheckCircle2 } from 'lucide-react';
import { SbbRouteData } from '../types';

interface HumanCheckpointModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => Promise<void>;
  sbbRoute: SbbRouteData | null;
}

export const HumanCheckpointModal: React.FC<HumanCheckpointModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  sbbRoute
}) => {
  const [isExecuting, setIsExecuting] = useState(false);
  const [executedSuccess, setExecutedSuccess] = useState(false);

  if (!isOpen) return null;

  const handleConfirmAction = async () => {
    setIsExecuting(true);
    await onConfirm();
    setIsExecuting(false);
    setExecutedSuccess(true);
    setTimeout(() => {
      setExecutedSuccess(false);
      onClose();
    }, 1800);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-950/60 backdrop-blur-md animate-fadeIn">
      <div className="bg-white rounded-3xl max-w-lg w-full p-6 shadow-2xl border border-gray-100 relative overflow-hidden">
        
        {/* Top Header */}
        <div className="flex items-center justify-between border-b border-gray-100 pb-4 mb-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-emerald-100 text-emerald-700 flex items-center justify-center font-bold">
              <ShieldAlert className="w-5 h-5 text-emerald-700" />
            </div>
            <div>
              <h3 className="text-lg font-extrabold text-gray-900 leading-tight">Human Checkpoint</h3>
              <p className="text-xs font-medium text-gray-500">Review & confirm agent actions</p>
            </div>
          </div>
          <button 
            onClick={onClose}
            className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 text-gray-500 flex items-center justify-center transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Content Body: Drafted Actions List */}
        {!executedSuccess ? (
          <>
            <p className="text-sm text-gray-600 mb-4 font-medium">
              The Agentic Engine drafted the following 2 modifications to resolve your schedule and route details:
            </p>

            <div className="space-y-3 mb-6">
              {/* Action 1: Reschedule Calendar */}
              <div className="p-4 rounded-2xl bg-amber-50/80 border border-amber-200/80 flex items-start gap-3">
                <div className="p-2 rounded-xl bg-amber-100 text-amber-800 shrink-0">
                  <Calendar className="w-5 h-5" />
                </div>
                <div className="flex-1">
                  <div className="flex items-center justify-between">
                    <h4 className="text-sm font-bold text-amber-950">Reschedule Focus Time</h4>
                    <span className="text-[10px] font-mono font-bold bg-amber-200 text-amber-900 px-2 py-0.5 rounded-md">Calendar API</span>
                  </div>
                  <p className="text-xs text-amber-900/80 mt-1">
                    Shift <strong>Focus time</strong> slot from <span className="line-through">09:15 – 09:45</span> to <strong>08:00 – 08:30</strong> to eliminate 15 min overlap with AI Hack Zürich.
                  </p>
                </div>
              </div>

              {/* Action 2: Add SBB Connection */}
              <div className="p-4 rounded-2xl bg-blue-50/80 border border-blue-200/80 flex items-start gap-3">
                <div className="p-2 rounded-xl bg-blue-100 text-blue-800 shrink-0">
                  <Train className="w-5 h-5" />
                </div>
                <div className="flex-1">
                  <div className="flex items-center justify-between">
                    <h4 className="text-sm font-bold text-blue-950">Save SBB Transit Route</h4>
                    <span className="text-[10px] font-mono font-bold bg-blue-200 text-blue-900 px-2 py-0.5 rounded-md">SBB Transport</span>
                  </div>
                  <p className="text-xs text-blue-900/80 mt-1">
                    S12 Train: <strong>Winterthur (08:42)</strong> → <strong>Zürich HB (09:07)</strong> + 12 min walk to venue (Arrival: 09:19).
                  </p>
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center justify-end gap-3 pt-2 border-t border-gray-100">
              <button
                onClick={onClose}
                disabled={isExecuting}
                className="px-4 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-700 hover:bg-gray-50 transition"
              >
                Cancel
              </button>
              <button
                onClick={handleConfirmAction}
                disabled={isExecuting}
                className="bg-emerald-700 hover:bg-emerald-800 text-white px-6 py-2.5 rounded-xl text-sm font-extrabold shadow-lg hover:shadow-xl transition-all flex items-center gap-2"
              >
                {isExecuting ? (
                  <>
                    <div className="w-4 h-4 rounded-full border-2 border-white border-t-transparent animate-spin"></div>
                    <span>Executing Tools...</span>
                  </>
                ) : (
                  <>
                    <Check className="w-4 h-4" />
                    <span>Approve & Execute</span>
                  </>
                )}
              </button>
            </div>
          </>
        ) : (
          /* Success Screen */
          <div className="py-8 flex flex-col items-center justify-center text-center space-y-3">
            <div className="w-16 h-16 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center animate-bounce">
              <CheckCircle2 className="w-10 h-10" />
            </div>
            <h4 className="text-xl font-extrabold text-gray-900">Execution Confirmed!</h4>
            <p className="text-sm text-gray-600 max-w-xs">
              Google Calendar updated & SBB ticket saved to your wallet. You are ready for AI Hack Zürich!
            </p>
          </div>
        )}

      </div>
    </div>
  );
};
