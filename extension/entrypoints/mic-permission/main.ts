const status = document.getElementById('status')!;
const retry = document.getElementById('retry')!;

async function ask() {
  status.className = '';
  status.textContent = "Waiting for Chrome's prompt…";
  retry.hidden = true;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((t) => t.stop());
    status.className = 'ok';
    status.textContent = 'Microphone enabled. You can close this tab.';
  } catch (err) {
    status.className = 'err';
    status.textContent = `Not allowed (${(err as Error).name}). Allow the microphone in the address bar, then try again.`;
    retry.hidden = false;
  }
}

retry.addEventListener('click', ask);
void ask();
