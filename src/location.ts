export function isTravelIntent(text: string): boolean {
  return /\b(get there|get to|how.*(?:reach|travel|go)|directions?|route|transport|journey|commut\w*|leave|leaving|depart\w*|arriv\w*|train|bus|walk|drive|driving|llegar|salir|salgo|salida|ruta|trayecto|transporte|viaj\w*|tren|autob[uú]s)\b/i.test(text);
}

export function currentPosition(geolocation: Pick<Geolocation, 'getCurrentPosition'> | undefined = navigator.geolocation): Promise<{ origin: string; accuracy: number }> {
  return new Promise((resolve, reject) => {
    if (!geolocation) {
      reject(new Error('Location is unavailable. Enter your starting point instead.'));
      return;
    }
    geolocation.getCurrentPosition(position => {
      const { latitude, longitude, accuracy } = position.coords;
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
        reject(new Error('Could not read your location. Enter your starting point instead.'));
        return;
      }
      resolve({ origin: `${latitude},${longitude}`, accuracy });
    }, error => {
      reject(new Error(error.code === 1
        ? 'Location permission was denied. Enter your starting point or allow location in your browser settings.'
        : error.code === 3
          ? 'Finding your location took too long. Try again or enter your starting point.'
          : 'Your location is unavailable. Try again or enter your starting point.'));
    }, { enableHighAccuracy: true, maximumAge: 30_000, timeout: 12_000 });
  });
}
