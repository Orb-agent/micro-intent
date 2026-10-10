import { Loader2, ShieldCheck } from 'lucide-react';
import { motion } from 'motion/react';
import { useEffect, useRef } from 'react';
interface Props {
  title: string;
  preview?: string;
  busy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/** Human checkpoint: nothing is written for the user until they press the confirm button. */
export function ConfirmSheet({ title, preview, busy, onConfirm, onCancel }: Props) {
  const cancelRef = useRef<HTMLButtonElement>(null);
  // Focus Cancel, not Confirm, so a stray Enter never approves a write.
  useEffect(() => cancelRef.current?.focus(), []);
  return (
    <motion.div
      className="mi-confirm"
      role="alertdialog"
      aria-label={title}
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 8 }}
      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
    >
      <div className="mi-confirm-badge">
        <ShieldCheck /> Needs your OK
      </div>
      <h3 className="mi-confirm-title">{title}?</h3>
      {preview && <p className="mi-confirm-preview">{preview}</p>}
      <p className="mi-confirm-fine">Nothing changes until you confirm.</p>
      <div className="mi-actions mi-confirm-actions">
        <button ref={cancelRef} type="button" className="mi-btn" data-style="secondary" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button type="button" className="mi-btn" data-style="primary" onClick={onConfirm} disabled={busy}>
          {busy ? <Loader2 className="mi-spin" /> : <ShieldCheck />}
          Confirm
        </button>
      </div>
    </motion.div>
  );
}
