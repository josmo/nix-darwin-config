/**
 * ============================================================================
 * GOOGLE CALENDAR BUSY-BLOCK & CLEAN PHONE-VIEW SYNC SCRIPT (v3 API EDITION)
 * ============================================================================
 *
 * WHAT THIS SCRIPT DOES:
 * 1. BUSY BLOCKING (Personal -> Work Primary):
 *    Reads events from shared personal/external calendars (`SOURCE_CALENDAR_IDS`)
 *    and creates merged, private "Busy" blocks on your primary work calendar
 *    so coworkers cannot double-book you.
 *
 * 2. CLEAN PHONE VIEW MIRROR (Work Primary -> Work Secondary Calendar):
 *    Optionally maintains a secondary calendar in your work account (e.g.,
 *    "Work (Phone View)") containing ONLY your real work meetings (excluding
 *    the personal "Busy" blocks). On your phone, uncheck your primary work
 *    calendar and check "Work (Phone View)" so you never see duplicate events!
 *
 * ----------------------------------------------------------------------------
 * SETUP INSTRUCTIONS:
 * ----------------------------------------------------------------------------
 * 1. Open https://script.google.com/ and open your project.
 * 2. IMPORTANT — ENABLE THE v3 CALENDAR SERVICE:
 *    - In the left sidebar, click "+" next to "Services".
 *    - Select "Google Calendar API" (keep Identifier as `Calendar`).
 *    - Click "Add".
 * 3. Paste this entire file into `Code.gs` and save.
 * 4. Configure `SOURCE_CALENDAR_IDS` and `ENABLE_PHONE_VIEW_MIRROR` in `CONFIG`.
 *
 * ----------------------------------------------------------------------------
 * ONE-TIME DUPLICATE / ORPHAN CLEANUP:
 * ----------------------------------------------------------------------------
 * 1. Leave `INCLUDE_UNTAGGED_ORPHANS: true` for your first run so it finds all
 *    blocks from earlier versions (`shared`, `private`, and untagged orphans).
 * 2. Set `DRY_RUN: true` and click "Run" on `syncBusyBlocks` to preview.
 * 3. Set `DRY_RUN: false` and click "Run" to apply changes and clean duplicates.
 * 4. Once clean, set `INCLUDE_UNTAGGED_ORPHANS: false` and save so all future
 *    runs use fast server-side filtering.
 *
 * ----------------------------------------------------------------------------
 * PHONE SETUP (WHEN `ENABLE_PHONE_VIEW_MIRROR: true`):
 * ----------------------------------------------------------------------------
 * 1. Run `syncBusyBlocks` once with `DRY_RUN: false` so the script creates and
 *    populates your `Work (Phone View)` secondary calendar.
 * 2. Open the Google Calendar app on your phone.
 * 3. Tap the Menu (hamburger icon) -> under your Work account, UNCHECK your
 *    primary work calendar and CHECK `Work (Phone View)`.
 *    (If you don't see `Work (Phone View)` right away, tap Settings -> your
 *    Work account -> tap "Show more" -> tap `Work (Phone View)` -> toggle "Sync" on).
 *
 * ----------------------------------------------------------------------------
 * AUTOMATING WITH TRIGGERS:
 * ----------------------------------------------------------------------------
 * 1. In the left sidebar of Apps Script, click the "Triggers" (clock) icon.
 * 2. Click "+ Add Trigger" (bottom right) and configure:
 *    - Choose which function to run: `syncBusyBlocks`
 *    - Select event source: "Time-driven"
 *    - Select type of time based trigger: "Minutes timer"
 *    - Select minute interval: "Every 15 minutes" (or "Every 30 minutes")
 * 3. Click "Save".
 *
 * ----------------------------------------------------------------------------
 * HOW TO UNINSTALL / WIPE ALL CREATED BLOCKS:
 * ----------------------------------------------------------------------------
 * 1. Delete or disable your time-driven trigger first.
 * 2. Set `DRY_RUN: false` (or `true` to preview) and save.
 * 3. Select `removeAllSyncedBlocks` in the top toolbar dropdown and click "Run".
 *    (Wipes both the "Busy" blocks on Primary and mirrored events on Phone View).
 * ============================================================================
 */

const CONFIG = {
  // Email addresses or Calendar IDs of the shared calendars to pull busy times from
  SOURCE_CALENDAR_IDS: [
    'joachim.hill@gmail.com',
    'joachim@pelo.tech'
  ],

  // Target calendar ID ('primary' targets your main work calendar)
  TARGET_CALENDAR_ID: 'primary',

  // How many days ahead to sync
  DAYS_IN_FUTURE: 21,

  // How many days back to look when cleaning up expired blocks
  PAST_DAYS_TO_CLEAN: 7,

  // Set to true to treat "Maybe" (Tentative) RSVP events as Busy; false to ignore them
  INCLUDE_MAYBE_EVENTS: false,

  // Set to true to treat unresponded ("Awaiting RSVP") invites as Busy; false to ignore them
  INCLUDE_UNRESPONDED_EVENTS: true,

  // --------------------------------------------------------------------------
  // CLEAN PHONE VIEW MIRROR CONFIGURATION
  // --------------------------------------------------------------------------
  // Set to true to mirror real work events onto a dedicated secondary calendar
  ENABLE_PHONE_VIEW_MIRROR: true,

  // Name of the secondary calendar in your work account (auto-created if missing)
  PHONE_VIEW_CALENDAR_NAME: 'Work (Phone View)',

  // --------------------------------------------------------------------------
  // APPEARANCE & TAGGING
  // --------------------------------------------------------------------------
  // Title, description & color shown ONLY to you on your primary work calendar
  // (Coworkers always just see "Busy" because visibility is set to private).
  // Color '8' is Graphite (Muted Gray). Set to null to use default calendar color.
  BLOCK_TITLE: 'Busy',
  BLOCK_DESCRIPTION: 'Auto-generated busy placeholder',
  BLOCK_COLOR_ID: '8',

  // Metadata key/values used to identify events created by this script
  TAG_KEY: 'managed_by',
  TAG_VALUE: 'calendar_busy_sync_script',
  PHONE_MIRROR_TAG_VALUE: 'calendar_phone_mirror_script',

  // Set to true ONCE to clean up untagged crash orphans or `private`-tagged blocks,
  // then set to false so future runs use fast server-side `sharedExtendedProperty` filtering.
  INCLUDE_UNTAGGED_ORPHANS: false,

  // --------------------------------------------------------------------------
  // RATE LIMIT & SAFETY CONTROLS
  // --------------------------------------------------------------------------
  // Delay (in ms) between calendar write calls to avoid Google API rate limits
  WRITE_SLEEP_MS: 250,

  // Maximum number of events to create/delete in a single execution across all syncs.
  MAX_WRITES_PER_RUN: 50,

  // Set to true to preview actions in the Execution Log without modifying calendars
  DRY_RUN: false
};

/**
 * Main entrypoint: Orchestrates locking, Busy-Block syncing, and Phone-View mirroring.
 */
function syncBusyBlocks() {
  ensureAdvancedCalendarEnabled();

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) {
    Logger.log('Sync already in progress. Skipping.');
    return;
  }

  try {
    if (CONFIG.DRY_RUN) {
      Logger.log('=== DRY RUN MODE ENABLED (No calendar changes will be made) ===');
    }

    const now = new Date();
    const cleanStart = addDays(now, -CONFIG.PAST_DAYS_TO_CLEAN);
    const syncEnd = addDays(now, CONFIG.DAYS_IN_FUTURE);

    // Track total write operations across both steps to stay within quota
    const budget = { remaining: CONFIG.MAX_WRITES_PER_RUN };

    // ========================================================================
    // STEP 1: Sync Personal Busy Blocks -> Primary Work Calendar
    // ========================================================================
    Logger.log('--- Step 1: Syncing Busy Blocks to Primary Calendar ---');
    const rawBusySlots = fetchBusySlotsFromSources(now, syncEnd);
    const desiredSlots = mergeIntervals(rawBusySlots);
    const existingBusyEvents = getManagedBusyEventsV3(CONFIG.TARGET_CALENDAR_ID, cleanStart, syncEnd);

    applyBusyDeltaSyncV3(CONFIG.TARGET_CALENDAR_ID, existingBusyEvents, desiredSlots, budget);

    // ========================================================================
    // STEP 2: Sync Real Work Events -> Clean Phone View Calendar (if enabled)
    // ========================================================================
    if (CONFIG.ENABLE_PHONE_VIEW_MIRROR) {
      Logger.log(`--- Step 2: Syncing Real Work Events to "${CONFIG.PHONE_VIEW_CALENDAR_NAME}" ---`);
      syncPhoneViewMirror(CONFIG.TARGET_CALENDAR_ID, cleanStart, now, syncEnd, budget);
    }
  } finally {
    lock.releaseLock();
  }
}

/**
 * Manual cleanup utility: Wipes all script-managed blocks across a wide window
 * (-30 days to +90 days) on both the primary calendar and the Phone View calendar.
 */
function removeAllSyncedBlocks() {
  ensureAdvancedCalendarEnabled();

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) {
    Logger.log('Another operation is currently running. Skipping.');
    return;
  }

  try {
    const now = new Date();
    const startWindow = addDays(now, -Math.max(CONFIG.PAST_DAYS_TO_CLEAN, 30));
    const endWindow = addDays(now, Math.max(CONFIG.DAYS_IN_FUTURE, 90));
    const budget = { remaining: CONFIG.MAX_WRITES_PER_RUN };

    if (CONFIG.DRY_RUN) {
      Logger.log('=== DRY RUN: removeAllSyncedBlocks ===');
    }

    // 1. Clean Busy blocks on Primary calendar
    const managedBusy = getManagedBusyEventsV3(CONFIG.TARGET_CALENDAR_ID, startWindow, endWindow);
    let deletedBusy = deleteEventListV3(CONFIG.TARGET_CALENDAR_ID, managedBusy, budget, 'Primary Busy Block');
    Logger.log(`Primary Calendar: Removed ${deletedBusy} of ${managedBusy.length} busy blocks.`);

    // 2. Clean mirrored events on Phone View calendar (if it exists)
    const phoneCalId = getOrCreatePhoneViewCalendarId(false);
    if (phoneCalId) {
      const managedMirror = getMirrorEventsV3(phoneCalId, startWindow, endWindow);
      let deletedMirror = deleteEventListV3(phoneCalId, managedMirror, budget, 'Phone View Event');
      Logger.log(`Phone View Calendar: Removed ${deletedMirror} of ${managedMirror.length} mirrored events.`);
    }
  } finally {
    lock.releaseLock();
  }
}

/**
 * Helper to delete a list of events while respecting DRY_RUN and write budget.
 */
function deleteEventListV3(calendarId, events, budget, label) {
  let deleted = 0;
  for (const event of events) {
    if (!CONFIG.DRY_RUN && budget.remaining <= 0) {
      Logger.log(`Reached MAX_WRITES_PER_RUN (${CONFIG.MAX_WRITES_PER_RUN}). Run again to finish deleting.`);
      break;
    }

    const rangeStr = formatRange(event.start, event.end);
    if (CONFIG.DRY_RUN) {
      Logger.log(`[WOULD DELETE ${label}] ${rangeStr}`);
      deleted++;
    } else {
      withRetry(() => Calendar.Events.remove(calendarId, event.id));
      Logger.log(`[DELETED ${label}] ${rangeStr}`);
      deleted++;
      budget.remaining--;
      Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
    }
  }
  return deleted;
}

// ============================================================================
// PART 1: BUSY BLOCK SYNC FUNCTIONS (Personal -> Work Primary)
// ============================================================================

/**
 * Queries the v3 Calendar API for managed busy blocks on the primary calendar.
 */
function getManagedBusyEventsV3(calendarId, start, end) {
  const results = [];
  let pageToken = null;

  do {
    const queryOptions = {
      timeMin: start.toISOString(),
      timeMax: end.toISOString(),
      singleEvents: true,
      maxResults: 250,
      pageToken: pageToken
    };

    if (!CONFIG.INCLUDE_UNTAGGED_ORPHANS) {
      queryOptions.sharedExtendedProperty = `${CONFIG.TAG_KEY}=${CONFIG.TAG_VALUE}`;
    }

    const response = withRetry(() => Calendar.Events.list(calendarId, queryOptions));

    if (response.items) {
      for (const item of response.items) {
        if (item.status === 'cancelled') continue;
        if (CONFIG.INCLUDE_UNTAGGED_ORPHANS && !isManagedBusyItem(item)) continue;

        const startTime = new Date(item.start.dateTime || item.start.date);
        const endTime = new Date(item.end.dateTime || item.end.date);
        const hasSharedTag = item.extendedProperties?.shared?.[CONFIG.TAG_KEY] === CONFIG.TAG_VALUE;

        results.push({
          id: item.id,
          start: startTime,
          end: endTime,
          hasSharedTag: hasSharedTag
        });
      }
    }
    pageToken = response.nextPageToken;
  } while (pageToken);

  // Sort events with the canonical `shared` tag first so duplicates get cleaned properly
  results.sort((a, b) => Number(b.hasSharedTag) - Number(a.hasSharedTag));
  return results;
}

/**
 * Checks if a raw v3 event resource on the primary calendar was created by this script.
 */
function isManagedBusyItem(item) {
  const shared = item.extendedProperties?.shared;
  const priv = item.extendedProperties?.private;

  if (shared?.[CONFIG.TAG_KEY] === CONFIG.TAG_VALUE) return true;
  if (priv?.[CONFIG.TAG_KEY] === CONFIG.TAG_VALUE) return true;

  if (item.summary === CONFIG.BLOCK_TITLE && item.description === CONFIG.BLOCK_DESCRIPTION) {
    return true;
  }

  return false;
}

/**
 * Delta-syncs busy blocks onto the primary work calendar.
 */
function applyBusyDeltaSyncV3(calendarId, existingEvents, desiredSlots, budget) {
  const desiredMap = new Map(
    desiredSlots.map(slot => [slotKey(slot.start, slot.end), slot])
  );

  let kept = 0, deleted = 0, created = 0;

  // 1. Evaluate existing managed events
  for (const event of existingEvents) {
    const key = slotKey(event.start, event.end);

    if (desiredMap.has(key) && event.hasSharedTag) {
      desiredMap.delete(key);
      kept++;
      if (CONFIG.DRY_RUN) {
        Logger.log(`[KEEP BUSY]   ${formatRange(event.start, event.end)}`);
      }
    } else {
      if (!CONFIG.DRY_RUN && budget.remaining <= 0) {
        Logger.log(`Reached MAX_WRITES_PER_RUN. Remaining busy deletions deferred to next run.`);
        break;
      }

      deleted++;
      if (CONFIG.DRY_RUN) {
        Logger.log(`[DELETE BUSY] ${formatRange(event.start, event.end)}`);
      } else {
        withRetry(() => Calendar.Events.remove(calendarId, event.id));
        budget.remaining--;
        Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
      }
    }
  }

  // 2. Create new busy slots
  for (const slot of desiredMap.values()) {
    if (!CONFIG.DRY_RUN && budget.remaining <= 0) {
      Logger.log(`Reached MAX_WRITES_PER_RUN. Remaining busy creations deferred to next run.`);
      break;
    }

    created++;
    if (CONFIG.DRY_RUN) {
      Logger.log(`[CREATE BUSY] ${formatRange(slot.start, slot.end)}`);
    } else {
      const eventResource = {
        summary: CONFIG.BLOCK_TITLE,
        description: CONFIG.BLOCK_DESCRIPTION,
        ...(CONFIG.BLOCK_COLOR_ID ? { colorId: CONFIG.BLOCK_COLOR_ID } : {}),
        start: { dateTime: slot.start.toISOString() },
        end: { dateTime: slot.end.toISOString() },
        visibility: 'private',
        transparency: 'opaque',
        reminders: { useDefault: false, overrides: [] },
        extendedProperties: {
          shared: {
            [CONFIG.TAG_KEY]: CONFIG.TAG_VALUE
          }
        }
      };

      withRetry(() => Calendar.Events.insert(eventResource, calendarId));
      budget.remaining--;
      Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
    }
  }

  const modePrefix = CONFIG.DRY_RUN ? '[DRY RUN] ' : '';
  Logger.log(`${modePrefix}Busy Sync complete — Kept: ${kept}, Created: ${created}, Deleted: ${deleted}`);
}

/**
 * Reads all source calendars and returns an array of { start, end } objects.
 */
function fetchBusySlotsFromSources(now, syncEnd) {
  const slots = [];

  for (const calId of CONFIG.SOURCE_CALENDAR_IDS) {
    const cal = CalendarApp.getCalendarById(calId);
    if (!cal) {
      Logger.log(`Warning: Cannot access calendar ${calId}`);
      continue;
    }

    for (const event of cal.getEvents(now, syncEnd)) {
      if (isBusyEvent(event, now)) {
        slots.push({ start: event.getStartTime(), end: event.getEndTime() });
      }
    }
  }

  return slots;
}

/**
 * Decides whether a source calendar event should block out time.
 */
function isBusyEvent(event, now) {
  if (event.isAllDayEvent()) return false;
  if (event.getTransparency() === CalendarApp.EventTransparency.TRANSPARENT) return false;
  if (event.getEventType?.() === CalendarApp.EventType.WORKING_LOCATION) return false;

  const status = event.getMyStatus();
  if (status === CalendarApp.GuestStatus.NO) return false;
  if (!CONFIG.INCLUDE_MAYBE_EVENTS && status === CalendarApp.GuestStatus.MAYBE) return false;
  if (!CONFIG.INCLUDE_UNRESPONDED_EVENTS && status === CalendarApp.GuestStatus.INVITED) return false;

  const start = event.getStartTime();
  const end = event.getEndTime();
  const durationMinutes = (end - start) / 60000;

  return end > now && durationMinutes >= 1;
}

// ============================================================================
// PART 2: CLEAN PHONE VIEW MIRROR FUNCTIONS (Work Primary -> Phone View)
// ============================================================================

/**
 * Mirrors genuine work events (excluding our synced Busy blocks) onto the
 * secondary Phone View calendar using a signature-based Delta Sync.
 */
function syncPhoneViewMirror(primaryCalId, cleanStart, now, syncEnd, budget) {
  const phoneCalId = getOrCreatePhoneViewCalendarId(!CONFIG.DRY_RUN);

  // 1. Fetch real work events from Primary Calendar in [now, syncEnd]
  const realWorkEvents = fetchRealWorkEventsV3(primaryCalId, now, syncEnd);

  // Build desired map keyed by a composite signature of the event's core fields
  // so any title, time, location, or link update triggers a clean replacement.
  const desiredMap = new Map();
  for (const ev of realWorkEvents) {
    desiredMap.set(ev.signature, ev);
  }

  // 2. Fetch existing mirrored events on Phone View Calendar (if calendar exists)
  const existingMirrors = phoneCalId
    ? getMirrorEventsV3(phoneCalId, cleanStart, syncEnd)
    : [];

  let kept = 0, deleted = 0, created = 0;

  // 3. Evaluate existing mirrored events (delete past or changed events)
  for (const mirror of existingMirrors) {
    if (desiredMap.has(mirror.signature)) {
      desiredMap.delete(mirror.signature);
      kept++;
      if (CONFIG.DRY_RUN) {
        Logger.log(`[KEEP MIRROR]   "${mirror.summary}" (${formatRange(mirror.start, mirror.end)})`);
      }
    } else {
      if (!CONFIG.DRY_RUN && budget.remaining <= 0) {
        Logger.log(`Reached MAX_WRITES_PER_RUN. Remaining mirror deletions deferred to next run.`);
        break;
      }

      deleted++;
      if (CONFIG.DRY_RUN) {
        Logger.log(`[DELETE MIRROR] "${mirror.summary}" (${formatRange(mirror.start, mirror.end)})`);
      } else {
        withRetry(() => Calendar.Events.remove(phoneCalId, mirror.id));
        budget.remaining--;
        Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
      }
    }
  }

  // 4. Create new/updated mirrored work events on Phone View Calendar
  for (const workEv of desiredMap.values()) {
    if (!CONFIG.DRY_RUN && budget.remaining <= 0) {
      Logger.log(`Reached MAX_WRITES_PER_RUN. Remaining mirror creations deferred to next run.`);
      break;
    }

    created++;
    if (CONFIG.DRY_RUN) {
      Logger.log(`[CREATE MIRROR] "${workEv.summary}" (${formatRange(workEv.start, workEv.end)})`);
    } else {
      const resource = {
        summary: workEv.summary,
        description: workEv.description,
        location: workEv.location,
        start: workEv.rawStart,
        end: workEv.rawEnd,
        reminders: { useDefault: false, overrides: [] }, // Avoid double notifications on phone
        extendedProperties: {
          shared: {
            [CONFIG.TAG_KEY]: CONFIG.PHONE_MIRROR_TAG_VALUE,
            mirror_sig: workEv.signature
          }
        }
      };

      withRetry(() => Calendar.Events.insert(resource, phoneCalId));
      budget.remaining--;
      Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
    }
  }

  const modePrefix = CONFIG.DRY_RUN ? '[DRY RUN] ' : '';
  Logger.log(`${modePrefix}Phone View Mirror complete — Kept: ${kept}, Created: ${created}, Deleted: ${deleted}`);
}

/**
 * Finds the secondary Phone View calendar by name, creating it if `createIfMissing` is true.
 */
function getOrCreatePhoneViewCalendarId(createIfMissing) {
  let pageToken = null;
  do {
    const list = withRetry(() => Calendar.CalendarList.list({ pageToken: pageToken }));
    if (list.items) {
      const match = list.items.find(c => c.summary === CONFIG.PHONE_VIEW_CALENDAR_NAME);
      if (match) return match.id;
    }
    pageToken = list.nextPageToken;
  } while (pageToken);

  if (!createIfMissing) {
    Logger.log(`[DRY RUN] Secondary calendar "${CONFIG.PHONE_VIEW_CALENDAR_NAME}" does not exist yet (will be auto-created when DRY_RUN is false).`);
    return null;
  }

  Logger.log(`Creating new secondary calendar: "${CONFIG.PHONE_VIEW_CALENDAR_NAME}"...`);
  const createdCal = withRetry(() => Calendar.Calendars.insert({
    summary: CONFIG.PHONE_VIEW_CALENDAR_NAME,
    description: 'Clean mirror of real work events (excludes personal busy blocks) for mobile viewing.',
    timeZone: Session.getScriptTimeZone()
  }));
  Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
  return createdCal.id;
}

/**
 * Fetches genuine work events from the primary calendar, skipping any Busy blocks
 * created by this script, working locations, and declined invitations.
 */
function fetchRealWorkEventsV3(calendarId, now, syncEnd) {
  const results = [];
  let pageToken = null;

  do {
    const response = withRetry(() => Calendar.Events.list(calendarId, {
      timeMin: now.toISOString(),
      timeMax: syncEnd.toISOString(),
      singleEvents: true,
      maxResults: 250,
      pageToken: pageToken
    }));

    if (response.items) {
      for (const item of response.items) {
        if (item.status === 'cancelled') continue;

        // 1. Skip our own synced Busy blocks!
        if (isManagedBusyItem(item)) continue;

        // 2. Skip Working Location / Out-of-Office / Focus Time metadata banners if desired
        if (item.eventType === 'workingLocation') continue;

        // 3. Skip events where the user declined the invite
        const selfAttendee = item.attendees?.find(a => a.self);
        if (selfAttendee?.responseStatus === 'declined') continue;

        const startTime = new Date(item.start.dateTime || item.start.date);
        const endTime = new Date(item.end.dateTime || item.end.date);
        if (endTime <= now) continue;

        // Preserve conference link (Google Meet / Zoom) inside description so it's clickable on phone
        const meetUri = item.hangoutLink || item.conferenceData?.entryPoints?.find(e => e.entryPointType === 'video')?.uri;
        let fullDescription = item.description || '';
        if (meetUri && !fullDescription.includes(meetUri)) {
          fullDescription = `Video Call: ${meetUri}\n\n${fullDescription}`.trim();
        }

        const summary = item.summary || '(No title)';
        const location = item.location || '';
        const signature = `${ item.id }_${startTime.getTime()}_${endTime.getTime()}_${summary}_${location}`;

        results.push({
          sourceId: item.id,
          summary: summary,
          description: fullDescription,
          location: location,
          rawStart: item.start,
          rawEnd: item.end,
          start: startTime,
          end: endTime,
          signature: signature
        });
      }
    }
    pageToken = response.nextPageToken;
  } while (pageToken);

  return results;
}

/**
 * Fetches existing mirrored events from the secondary Phone View calendar.
 */
function getMirrorEventsV3(phoneCalId, start, end) {
  const results = [];
  let pageToken = null;

  do {
    const response = withRetry(() => Calendar.Events.list(phoneCalId, {
      timeMin: start.toISOString(),
      timeMax: end.toISOString(),
      singleEvents: true,
      sharedExtendedProperty: `${CONFIG.TAG_KEY}=${CONFIG.PHONE_MIRROR_TAG_VALUE}`,
      maxResults: 250,
      pageToken: pageToken
    }));

    if (response.items) {
      for (const item of response.items) {
        if (item.status === 'cancelled') continue;
        const startTime = new Date(item.start.dateTime || item.start.date);
        const endTime = new Date(item.end.dateTime || item.end.date);
        const sig = item.extendedProperties?.shared?.mirror_sig || `${item.id}_${startTime.getTime()}_${endTime.getTime()}`;

        results.push({
          id: item.id,
          summary: item.summary || '(No title)',
          start: startTime,
          end: endTime,
          signature: sig
        });
      }
    }
    pageToken = response.nextPageToken;
  } while (pageToken);

  return results;
}

// ============================================================================
// PART 3: SHARED UTILITIES & HELPERS
// ============================================================================

/**
 * Executes a Calendar API operation with exponential backoff if rate-limited.
 */
function withRetry(fn, maxRetries = 4) {
  let delayMs = 2000;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return fn();
    } catch (err) {
      const msg = err.message || '';
      const isRateLimit = (
        msg.includes('too many calendars or calendar events') ||
        msg.includes('Service invoked too many times') ||
        msg.includes('Rate Limit Exceeded') ||
        msg.includes('User Rate Limit Exceeded') ||
        msg.includes('quotaExceeded')
      );

      if (!isRateLimit || attempt === maxRetries) {
        throw err;
      }

      Logger.log(`Rate limit hit (attempt ${attempt}/${maxRetries}). Pausing ${delayMs / 1000}s before retrying...`);
      Utilities.sleep(delayMs);
      delayMs *= 2;
    }
  }
}

/**
 * Combines overlapping or back-to-back time slots.
 */
function mergeIntervals(intervals) {
  if (!intervals.length) return [];

  intervals.sort((a, b) => a.start - b.start);
  const merged = [{ ...intervals[0] }];

  for (const current of intervals.slice(1)) {
    const last = merged[merged.length - 1];

    if (current.start <= last.end) {
      last.end = new Date(Math.max(last.end, current.end));
    } else {
      merged.push({ ...current });
    }
  }

  return merged;
}

/**
 * Verifies that the Google Calendar Advanced Service is enabled.
 */
function ensureAdvancedCalendarEnabled() {
  if (typeof Calendar === 'undefined' || !Calendar.Events) {
    throw new Error(
      'Google Calendar API Service is not enabled! In the left sidebar, click "+" next to "Services", select "Google Calendar API", and click "Add".'
    );
  }
}

function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function slotKey(start, end) {
  return `${start.getTime()}_${end.getTime()}`;
}

function formatRange(start, end) {
  const tz = Session.getScriptTimeZone();
  const dayStr = Utilities.formatDate(start, tz, 'EEE, MMM d, yyyy');
  const startStr = Utilities.formatDate(start, tz, 'h:mm a');
  const endStr = Utilities.formatDate(end, tz, 'h:mm a');
  return `${dayStr}: ${startStr} - ${endStr}`;
}
