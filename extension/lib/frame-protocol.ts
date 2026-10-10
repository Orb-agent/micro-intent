// Messages between the content script and the overlay iframe. They travel over a private
// MessageChannel: the content script hands the port to the frame together with a nonce from the
// frame's URL. The frame lives in a closed shadow root, so page scripts can neither read the nonce
// nor see the traffic, and cannot fake a push-to-talk press or an open.
import type { OverlayLayout, Target } from '../src/ui/host';

export type ToFrame =
  | { mi: 'open'; target: Target }
  | { mi: 'ptt'; down: boolean }
  | { mi: 'hidden' }
  | { mi: 'viewport'; maxHeight: number };

export type FromFrame =
  | { mi: 'ready' }
  | { mi: 'layout'; layout: OverlayLayout }
  | { mi: 'drag'; dx: number; dy: number }
  | { mi: 'close' };

/** First message on the window, carrying the channel port. */
export interface PortHandoff {
  mi: 'port';
  nonce: string;
}
