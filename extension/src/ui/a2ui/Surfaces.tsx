import { A2uiSurface } from '@a2ui/react/v0_9';
import { MessageProcessor, type ActionListener, type SurfaceModel } from '@a2ui/web_core/v0_9';
import { useCallback, useEffect, useRef, useState } from 'react';
import { catalog } from './catalog';
import { A2UI_VERSION, CATALOG_ID, type A2uiMessage } from './protocol';

/**
 * Owns the A2UI message processor for one overlay session. Surfaces persist across turns so a
 * later turn can delete or update them (e.g. `/action` deletes the surface it confirmed).
 */
export function useA2ui(onAction: ActionListener, onError: (msg: string) => void) {
  const actionRef = useRef(onAction);
  actionRef.current = onAction;
  const errorRef = useRef(onError);
  errorRef.current = onError;
  const [surfaces, setSurfaces] = useState<SurfaceModel<any>[]>([]);
  const current = useRef<{ processor: MessageProcessor; dispose: () => void } | undefined>(undefined);

  /** Starts a fresh set of surfaces, e.g. for a new intent. */
  const reset = useCallback(() => {
    current.current?.dispose();
    const processor = new MessageProcessor([catalog], (a) => actionRef.current(a));
    const sync = () => setSurfaces(Array.from(processor.model.surfacesMap.values()));
    const created = processor.onSurfaceCreated(sync);
    const deleted = processor.onSurfaceDeleted(sync);
    current.current = {
      processor,
      dispose: () => {
        created.unsubscribe();
        deleted.unsubscribe();
        processor.dispose();
      },
    };
    setSurfaces([]);
    return processor;
  }, []);

  useEffect(() => {
    reset();
    return () => current.current?.dispose();
  }, [reset]);

  /** Feeds one turn's cards. One message at a time: a bad message must not drop the rest. */
  const process = useCallback(
    (messages: A2uiMessage[]) => {
      const processor = current.current?.processor ?? reset();
      for (const m of messages) {
        try {
          processor.processMessages([m]);
        } catch (err) {
          console.warn('[micro-intent] rejected A2UI message', err, m);
          errorRef.current('Part of the answer could not be shown.');
        }
      }
    },
    [reset],
  );

  return { surfaces, process, reset };
}

export function Surfaces({ surfaces }: { surfaces: SurfaceModel<any>[] }) {
  return (
    <>
      {surfaces.map((s) => (
        <A2uiSurface key={s.id} surface={s} />
      ))}
    </>
  );
}

/** A local DoneCard surface for a confirmed action. */
export function doneSurface(id: string, title: string, text?: string, link?: { label: string; url: string }): A2uiMessage[] {
  return [
    { version: A2UI_VERSION, createSurface: { surfaceId: id, catalogId: CATALOG_ID } },
    {
      version: A2UI_VERSION,
      updateComponents: { surfaceId: id, components: [{ id: 'root', component: 'DoneCard', title, text, link }] },
    },
  ] as A2uiMessage[];
}
