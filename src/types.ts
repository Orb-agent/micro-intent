export type OrbState = 'at_rest' | 'listening' | 'connecting' | 'ready';

export interface CalendarEventItem {
  id: string;
  title: string;
  startTime: string;
  endTime: string;
  date: string;
  type: 'focus' | 'event' | 'meeting' | 'routine';
  color: string;
  location?: string;
  isProposedShift?: boolean;
}

export interface SbbLeg {
  from: string;
  to: string;
  departure: string;
  arrival: string;
  line?: string;
  mode: 'train' | 'tram' | 'walk' | 'bus';
}

export interface SbbRouteData {
  id: string;
  from: string;
  to: string;
  departureTime: string;
  arrivalTime: string;
  totalDurationMinutes: number;
  transfers: number;
  arrivalNotice: string;
  onwardJourneyMinutes: number;
  legs: SbbLeg[];
}

export interface IntentState {
  isGazeActive: boolean;
  gazeTarget: string;
  userQuery: string;
  orbState: OrbState;
  isListening: boolean;
  isProcessing: boolean;
  hasConflict: boolean;
  overlapMinutes: number;
  proposedShift: {
    originalSlot: string;
    newSlot: string;
    title: string;
  };
  sbbRoute: SbbRouteData | null;
  isConfirmed: boolean;
}
