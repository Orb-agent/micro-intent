# Manual device check

This checklist is for a human tester with a webcam and speakers or headphones. It describes checks to perform; it does not claim that physical-device or browser QA has already been completed.

## Webcam gaze

- Use a current desktop browser on HTTPS or `localhost`, with a working webcam.
- Load the app and confirm that the camera stays off before selecting **Control with gaze**.
- Select the control, allow camera access, and confirm that the nine-point calibration appears.
- Click each target three times while looking at it. Confirm that progress advances through all nine targets and then closes.
- Move your gaze across the event and route context areas. Confirm the gaze marker follows the prediction and the context indicator changes only over supported context elements.
- Turn gaze off. Confirm the webcam-in-use indicator disappears and the pointer remains usable.
- Start gaze again, then switch tabs. Confirm camera use stops. Return and explicitly restart to calibrate again.
- Repeat with camera permission denied and with the CDN unavailable. Confirm an English error appears and pointer interaction remains available.

Record the browser/version, operating system, webcam model, permission outcome, and any prediction or cleanup problems. Webcam gaze is experimental; accuracy varies with camera quality, lighting, browser, and user setup.

## Read-aloud

- Confirm the app does not speak until the tester activates its read-aloud control.
- Start speech, start a different passage, and confirm the new passage replaces the previous one.
- Stop speech and switch tabs during speech. Confirm playback stops in both cases.
- Check that an installed English voice is selected when available and that the `en-US` language fallback is used otherwise.
- On a browser without Speech Synthesis support, confirm that the control reports the feature as unavailable without interrupting pointer or keyboard use.

## Current location for travel

- On HTTPS or localhost, ask “How do I get there?” or “When should I leave?”. Grant location access and check that **Current location** replaces the empty origin. Nothing should request location on page load or on a calendar-only question.
- Open Maps and verify that its origin matches your device location. Location accuracy depends on the device; desktop results can be approximate.
- Deny permission, disable location services, and test a timeout: an English message must offer a manual starting point, without claiming a route was calculated.
- Type a station or address and plan again. It must override device location. Select **Use current location** to return to device location.
- Repeat on Luma with the extension. A site's Permissions Policy may block geolocation; use a manual origin or the standalone app in that case.
- Coordinates remain in memory and are sent to the planner to prepare the Maps link, not to the summary model. Opening that link shares them with Maps. They are not saved in browser storage.
- The app displays the event's arrival target. It does not currently calculate a live departure time; choose **Arrive by** in Maps and set the shown date/time. SBB opens its timetable homepage and does not prefill the origin.

Automated checks cover intent detection, coordinates in the Maps link, and permission/unavailable/timeout failures with a stub location provider. Physical-device GPS and permission prompts still require the manual checks above.

Implementation references: [Geolocation API](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/getCurrentPosition) and [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started).
