import { useState } from 'react';

export interface GazeCalibrationProps {
  onSample: (x: number, y: number) => void;
  onComplete: () => void;
  onCancel: () => void;
}

const targets = [
  { left: '8%', top: '12%' },
  { left: '50%', top: '12%' },
  { left: '92%', top: '12%' },
  { left: '8%', top: '50%' },
  { left: '50%', top: '50%' },
  { left: '92%', top: '50%' },
  { left: '8%', top: '88%' },
  { left: '50%', top: '88%' },
  { left: '92%', top: '88%' },
];

const CLICKS_PER_TARGET = 3;

export function GazeCalibration({ onSample, onComplete, onCancel }: GazeCalibrationProps) {
  const [targetIndex, setTargetIndex] = useState(0);
  const [clicksOnTarget, setClicksOnTarget] = useState(0);
  const [completedClicks, setCompletedClicks] = useState(0);

  const handleTargetClick = (event: React.MouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    onSample(event.clientX, event.clientY);

    const nextClickCount = clicksOnTarget + 1;
    setCompletedClicks((count) => count + 1);
    if (nextClickCount === CLICKS_PER_TARGET) {
      if (targetIndex === targets.length - 1) {
        onComplete();
        return;
      }
      setTargetIndex((index) => index + 1);
      setClicksOnTarget(0);
    } else {
      setClicksOnTarget(nextClickCount);
    }
  };

  return (
    <div className="gaze-calibration" role="dialog" aria-modal="true" aria-labelledby="gaze-calibration-title">
      <style>{`
        .gaze-calibration{position:fixed;inset:0;z-index:10000;background:rgba(8,16,28,.94);color:#f8fafc;font-family:Inter,ui-sans-serif,system-ui,sans-serif;overflow:hidden}
        .gaze-calibration__panel{position:absolute;top:20px;left:50%;transform:translateX(-50%);width:min(92vw,620px);box-sizing:border-box;padding:16px 20px;border:1px solid rgba(148,163,184,.25);border-radius:18px;background:rgba(15,23,42,.9);text-align:center;box-shadow:0 16px 48px rgba(0,0,0,.28)}
        .gaze-calibration__eyebrow{margin:0 0 6px;color:#6ee7b7;font-size:11px;font-weight:800;letter-spacing:.13em;text-transform:uppercase}
        .gaze-calibration__title{margin:0;font-size:clamp(18px,3vw,24px);font-weight:750;letter-spacing:-.03em}
        .gaze-calibration__copy{margin:8px 0 12px;color:#cbd5e1;font-size:14px;line-height:1.45}
        .gaze-calibration__progress{display:flex;align-items:center;justify-content:center;gap:10px;color:#94a3b8;font-size:12px}
        .gaze-calibration__track{width:min(40vw,180px);height:5px;border-radius:99px;background:#334155;overflow:hidden}
        .gaze-calibration__fill{height:100%;background:#34d399;transition:width .2s ease}
        .gaze-calibration__cancel{position:absolute;top:24px;right:24px;border:1px solid #64748b;border-radius:999px;background:rgba(15,23,42,.85);padding:9px 15px;color:#e2e8f0;font-size:13px;font-weight:650;cursor:pointer}
        .gaze-calibration__cancel:hover{background:#334155}
        .gaze-calibration__target{position:absolute;width:46px;height:46px;transform:translate(-50%,-50%);border:0;border-radius:50%;padding:0;background:transparent;cursor:pointer;display:grid;place-items:center;touch-action:manipulation}
        .gaze-calibration__target:focus-visible{outline:3px solid #a7f3d0;outline-offset:6px}
        .gaze-calibration__ring{position:absolute;width:34px;height:34px;border:2px solid rgba(110,231,183,.65);border-radius:50%;transition:transform .15s ease,background .15s ease}
        .gaze-calibration__dot{width:13px;height:13px;border-radius:50%;background:#34d399;box-shadow:0 0 18px rgba(52,211,153,.8);transition:transform .15s ease}
        .gaze-calibration__target:hover .gaze-calibration__dot{transform:scale(1.25)}
        .gaze-calibration__counter{position:absolute;left:50%;top:calc(100% + 9px);transform:translateX(-50%);white-space:nowrap;border-radius:99px;background:#0f172a;padding:3px 8px;color:#a7f3d0;font-size:11px;font-weight:700}
        @media(max-width:560px){.gaze-calibration__panel{top:14px;padding:13px 14px}.gaze-calibration__copy{font-size:12px;margin:6px 0 9px}.gaze-calibration__cancel{top:auto;bottom:16px;right:16px}.gaze-calibration__target{width:42px;height:42px}}
      `}</style>

      <section className="gaze-calibration__panel">
        <p className="gaze-calibration__eyebrow">Eye-tracking calibration · experimental</p>
        <h2 className="gaze-calibration__title" id="gaze-calibration-title">Look at the dot and click it three times</h2>
        <p className="gaze-calibration__copy">Keep your head still and follow the dots across the screen. Camera images are processed on this device.</p>
        <div className="gaze-calibration__progress" aria-live="polite">
          <span>Point {targetIndex + 1} of {targets.length} · click {clicksOnTarget + 1} of {CLICKS_PER_TARGET}</span>
          <span className="gaze-calibration__track" aria-hidden="true"><span className="gaze-calibration__fill" style={{ width: `${(completedClicks / (targets.length * CLICKS_PER_TARGET)) * 100}%`, display: 'block' }} /></span>
        </div>
      </section>

      <button className="gaze-calibration__cancel" type="button" onClick={onCancel}>Cancel</button>

      {targets.map((target, index) => index === targetIndex ? (
        <button
          key={index}
          type="button"
          className="gaze-calibration__target"
          style={{ left: target.left, top: target.top }}
          onClick={handleTargetClick}
          aria-label={`Calibration point ${index + 1}, click ${clicksOnTarget + 1} of ${CLICKS_PER_TARGET}`}
        >
          <span className="gaze-calibration__ring" />
          <span className="gaze-calibration__dot" />
          <span className="gaze-calibration__counter">{clicksOnTarget}/{CLICKS_PER_TARGET}</span>
        </button>
      ) : null)}
    </div>
  );
}
