import { createRoot } from 'react-dom/client';
import { createExtensionHost } from '@/lib/extension-host';
import { OverlayApp } from '@/src/ui/OverlayApp';
import '@/src/ui/styles.css';

createRoot(document.getElementById('root')!).render(<OverlayApp host={createExtensionHost()} />);
