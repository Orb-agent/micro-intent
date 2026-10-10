import { useCallback, useEffect, useRef, useState } from 'react';

export type GazeStatus = 'off' | 'loading' | 'calibrating' | 'active' | 'error';

export interface GazePoint {
  x: number;
  y: number;
}

interface WebGazerPrediction {
  x: number;
  y: number;
}

interface WebGazerApi {
  begin: () => Promise<unknown>;
  end: () => unknown;
  setGazeListener: (listener: (prediction: WebGazerPrediction | null) => void) => WebGazerApi;
  clearGazeListener?: () => WebGazerApi;
  recordScreenPosition: (x: number, y: number, eventType?: 'click' | 'move') => WebGazerApi;
  saveDataAcrossSessions: (save: boolean) => WebGazerApi;
  applyKalmanFilter?: (enabled: boolean) => WebGazerApi;
  removeMouseEventListeners?: () => WebGazerApi;
  showVideoPreview?: (enabled: boolean) => WebGazerApi;
  showPredictionPoints?: (enabled: boolean) => WebGazerApi;
  stopVideo?: () => unknown;
}

declare global {
  interface Window {
    webgazer?: WebGazerApi;
    saveDataAcrossSessions?: boolean;
  }
}

// The pinned jsDelivr package is the official brownhci/WebGazer build. Its
// begin/setGazeListener/recordScreenPosition API is documented at:
// https://github.com/brownhci/WebGazer/wiki/Top-Level-API
// The project's official setup guide is https://webgazer.cs.brown.edu/.
const WEBGAZER_SCRIPT_ID = 'webgazer-script-3-5-3';
const WEBGAZER_SCRIPT_URL = 'https://cdn.jsdelivr.net/npm/webgazer@3.5.3/dist/webgazer.js';

let webgazerLoad: Promise<WebGazerApi> | null = null;

function loadWebGazer(): Promise<WebGazerApi> {
  if (window.webgazer) return Promise.resolve(window.webgazer);
  if (webgazerLoad) return webgazerLoad;

  webgazerLoad = new Promise<WebGazerApi>((resolve, reject) => {
    let script = document.getElementById(WEBGAZER_SCRIPT_ID) as HTMLScriptElement | null;
    let settled = false;
    let timeoutId = 0;

    const removeFailedScript = () => {
      if (script && document.getElementById(WEBGAZER_SCRIPT_ID) === script) script.remove();
    };
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeoutId);
      script?.removeEventListener('load', handleLoad);
      script?.removeEventListener('error', handleError);
      if (error) {
        removeFailedScript();
        reject(error);
      } else if (window.webgazer) {
        resolve(window.webgazer);
      } else {
        removeFailedScript();
        reject(new Error('WebGazer loaded, but could not start eye tracking.'));
      }
    };
    const handleLoad = () => {
      finish();
    };
    const handleError = () => finish(new Error('Could not load WebGazer from the CDN.'));

    timeoutId = window.setTimeout(() => {
      finish(new Error('WebGazer took longer than 20 seconds to load.'));
    }, 20_000);

    if (!script) {
      script = document.createElement('script');
      script.id = WEBGAZER_SCRIPT_ID;
      script.src = WEBGAZER_SCRIPT_URL;
      script.async = true;
      script.crossOrigin = 'anonymous';
      script.addEventListener('load', handleLoad, { once: true });
      script.addEventListener('error', handleError, { once: true });
      document.head.appendChild(script);
      return;
    }

    if (window.webgazer) {
      resolve(window.webgazer);
      return;
    }
    script.addEventListener('load', handleLoad, { once: true });
    script.addEventListener('error', handleError, { once: true });
  }).catch((error: unknown) => {
    webgazerLoad = null;
    throw error;
  });

  return webgazerLoad;
}

function stopCameraTracks(): void {
  const video = document.getElementById('webgazerVideoFeed') as HTMLVideoElement | null;
  video?.srcObject &&
    (video.srcObject as MediaStream).getTracks().forEach((track) => track.stop());
}

function stopWebGazer(webgazer: WebGazerApi | null | undefined): void {
  try {
    webgazer?.clearGazeListener?.();
  } catch {
    // Continue stopping the camera even if listener cleanup fails.
  }
  try {
    webgazer?.stopVideo?.();
  } catch {
    // stopVideo may run before WebGazer finishes building its preview nodes.
  }
  try {
    stopCameraTracks();
  } catch {
    // The stream may already have been released.
  }
  try {
    webgazer?.end();
  } catch {
    // end can run while begin is still initializing; its completion path retries.
  }
}

export function useGaze() {
  const [status, setStatus] = useState<GazeStatus>('off');
  const [error, setError] = useState('');
  const [point, setPoint] = useState<GazePoint | null>(null);
  const statusRef = useRef<GazeStatus>('off');
  const runIdRef = useRef(0);
  const webgazerRef = useRef<WebGazerApi | null>(null);
  const smoothedPointRef = useRef<GazePoint | null>(null);

  const updateStatus = useCallback((nextStatus: GazeStatus) => {
    statusRef.current = nextStatus;
    setStatus(nextStatus);
  }, []);

  const stop = useCallback(() => {
    runIdRef.current += 1;
    const webgazer = webgazerRef.current ?? window.webgazer;
    webgazerRef.current = null;
    // Capture and stop the stream before end() removes WebGazer's video node.
    stopWebGazer(webgazer);
    smoothedPointRef.current = null;
    setPoint(null);
    setError('');
    updateStatus('off');
  }, [updateStatus]);

  const start = useCallback(async () => {
    if (statusRef.current === 'loading' || statusRef.current === 'calibrating' || statusRef.current === 'active') return;

    const runId = ++runIdRef.current;
    setError('');
    setPoint(null);
    smoothedPointRef.current = null;
    updateStatus('loading');

    let activeWebGazer: WebGazerApi | null = null;
    try {
      const webgazer = await loadWebGazer();
      activeWebGazer = webgazer;
      if (runId !== runIdRef.current) return;

      // WebGazer otherwise stores calibration samples in browser storage.
      window.saveDataAcrossSessions = false;
      webgazer.saveDataAcrossSessions(false);
      webgazer.applyKalmanFilter?.(true);
      // The camera feed and WebGazer's red prediction marker would otherwise
      // sit behind or above the full-screen calibration targets.
      webgazer.showVideoPreview?.(false);
      webgazer.showPredictionPoints?.(false);
      webgazerRef.current = webgazer;

      await webgazer.begin();
      if (runId !== runIdRef.current) {
        stopWebGazer(webgazer);
        if (webgazerRef.current === webgazer) webgazerRef.current = null;
        return;
      }

      // Keep training limited to the explicit calibration clicks below. WebGazer
      // installs global click and move listeners as part of begin().
      webgazer.removeMouseEventListeners?.();
      webgazer.setGazeListener((prediction) => {
        if (!prediction || runId !== runIdRef.current) return;
        const { x, y } = prediction;
        if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x > window.innerWidth || y > window.innerHeight) return;

        const previous = smoothedPointRef.current;
        const next = previous
          ? { x: previous.x * 0.72 + x * 0.28, y: previous.y * 0.72 + y * 0.28 }
          : { x, y };
        smoothedPointRef.current = next;
        setPoint(next);
      });
      updateStatus('calibrating');
    } catch (cause) {
      const webgazer = webgazerRef.current ?? activeWebGazer;
      if (webgazer) stopWebGazer(webgazer);
      if (webgazerRef.current === webgazer) webgazerRef.current = null;
      if (runId !== runIdRef.current) return;
      const message = cause instanceof Error ? cause.message : 'Could not start the camera.';
      setError(`${message} Eye tracking is unavailable; you can continue with the pointer.`);
      updateStatus('error');
    }
  }, [updateStatus]);

  const calibrate = useCallback((x: number, y: number) => {
    if (statusRef.current !== 'calibrating') return;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    webgazerRef.current?.recordScreenPosition(x, y, 'click');
  }, []);

  const finishCalibration = useCallback(() => {
    if (statusRef.current === 'calibrating') updateStatus('active');
  }, [updateStatus]);

  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'hidden' && statusRef.current !== 'off') stop();
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      runIdRef.current += 1;
      const webgazer = webgazerRef.current ?? window.webgazer;
      webgazerRef.current = null;
      smoothedPointRef.current = null;
      stopWebGazer(webgazer);
    };
  }, [stop]);

  return { status, error, point, start, stop, calibrate, finishCalibration };
}
