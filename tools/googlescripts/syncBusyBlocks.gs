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
  withScriptLock(() => {
    if (CONFIG.DRY_RUN) {
      Logger.log('=== DRY RUN MODE ENABLED (No calendar changes will be made) ===');
    }

    const now = new Date();
    const cleanStart = addDays(now, -CONFIG.PAST_DAYS_TO_CLEAN);
    const syncEnd = addDays(now, CONFIG.DAYS_IN_FUTURE);

    // Track total write operations across both steps to stay within quota
    const budget = { remaining: CONFIG.MAX_WRITES_PER_RUN };

    // One read of the primary calendar serves both steps: our Busy blocks + real work events
    const primaryEvents = listEvents(CONFIG.TARGET_CALENDAR_ID, cleanStart, syncEnd);

    // ========================================================================
    // STEP 1: Sync Personal Busy Blocks -> Primary Work Calendar
    // ========================================================================
    Logger.log('--- Step 1: Syncing Busy Blocks to Primary Calendar ---');
    const existingBlocks = primaryEvents.filter(isManagedBusyItem);
    const desiredBlocks = mergeIntervals(fetchBusySlotsFromSources(now, syncEnd)).map(toBusyBlock);

    deltaSync(CONFIG.TARGET_CALENDAR_ID, existingBlocks, desiredBlocks, busyKey, budget, 'BUSY');

    // ========================================================================
    // STEP 2: Sync Real Work Events -> Clean Phone View Calendar (if enabled)
    // ========================================================================
    if (CONFIG.ENABLE_PHONE_VIEW_MIRROR) {
      Logger.log(`--- Step 2: Syncing Real Work Events to "${CONFIG.PHONE_VIEW_CALENDAR_NAME}" ---`);
      const workEvents = primaryEvents.filter(item => isRealWorkEvent(item, now));
      syncPhoneViewMirror(workEvents, cleanStart, syncEnd, budget);
    }
  });
}

/**
 * Manual cleanup utility: Wipes all script-managed blocks across a wide window
 * (-30 days to +90 days) on both the primary calendar and the Phone View calendar.
 */
function removeAllSyncedBlocks() {
  withScriptLock(() => {
    if (CONFIG.DRY_RUN) {
      Logger.log('=== DRY RUN: removeAllSyncedBlocks ===');
    }

    const now = new Date();
    const start = addDays(now, -Math.max(CONFIG.PAST_DAYS_TO_CLEAN, 30));
    const end = addDays(now, Math.max(CONFIG.DAYS_IN_FUTURE, 90));
    const budget = { remaining: CONFIG.MAX_WRITES_PER_RUN };

    // Delta-syncing against an empty desired set deletes every managed event
    const busyBlocks = listTaggedEvents(CONFIG.TARGET_CALENDAR_ID, start, end, CONFIG.TAG_VALUE);
    deltaSync(CONFIG.TARGET_CALENDAR_ID, busyBlocks, [], busyKey, budget, 'BUSY');

    const phoneCalId = findPhoneViewCalendarId();
    if (phoneCalId) {
      const mirrors = listTaggedEvents(phoneCalId, start, end, CONFIG.PHONE_MIRROR_TAG_VALUE);
      deltaSync(phoneCalId, mirrors, [], mirrorKey, budget, 'MIRROR');
    }
  });
}

// ============================================================================
// PART 1: BUSY BLOCK SYNC FUNCTIONS (Personal -> Work Primary)
// ============================================================================

/**
 * Checks if an event on the primary calendar is a Busy block created by this script.
 */
function isManagedBusyItem(item) {
  return item.extendedProperties?.shared?.[CONFIG.TAG_KEY] === CONFIG.TAG_VALUE;
}

/**
 * Busy blocks are identified by their exact time range.
 */
function busyKey(item) {
  return `${eventDate(item.start).getTime()}_${eventDate(item.end).getTime()}`;
}

/**
 * Builds the event resource for a busy block covering a merged time slot.
 */
function toBusyBlock(slot) {
  return {
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
}

/**
 * Reads all source calendars and returns an array of { start, end } busy slots.
 */
function fetchBusySlotsFromSources(now, syncEnd) {
  const slots = [];

  for (const calId of CONFIG.SOURCE_CALENDAR_IDS) {
    let items;
    try {
      items = listEvents(calId, now, syncEnd);
    } catch (err) {
      Logger.log(`Warning: Cannot access calendar ${calId}: ${err.message}`);
      continue;
    }

    for (const item of items.filter(isBusySourceEvent)) {
      slots.push({ start: eventDate(item.start), end: eventDate(item.end) });
    }
  }

  return slots;
}

/**
 * Decides whether a source calendar event should block out time.
 */
function isBusySourceEvent(item) {
  if (item.start.date) return false; // All-day event
  if (item.transparency === 'transparent') return false;
  if (item.eventType === 'workingLocation') return false;

  const status = selfResponse(item);
  if (status === 'declined') return false;
  if (!CONFIG.INCLUDE_MAYBE_EVENTS && status === 'tentative') return false;
  if (!CONFIG.INCLUDE_UNRESPONDED_EVENTS && status === 'needsAction') return false;

  return eventDate(item.end) - eventDate(item.start) >= 60000;
}

// ============================================================================
// PART 2: CLEAN PHONE VIEW MIRROR FUNCTIONS (Work Primary -> Phone View)
// ============================================================================

/**
 * Mirrors genuine work events onto the secondary Phone View calendar
 * using a signature-based Delta Sync.
 */
function syncPhoneViewMirror(workEvents, cleanStart, syncEnd, budget) {
  let phoneCalId = findPhoneViewCalendarId();
  if (!phoneCalId) {
    if (CONFIG.DRY_RUN) {
      Logger.log(`[DRY RUN] Secondary calendar "${CONFIG.PHONE_VIEW_CALENDAR_NAME}" does not exist yet (will be auto-created when DRY_RUN is false).`);
    } else {
      phoneCalId = createPhoneViewCalendar();
    }
  }

  const desiredMirrors = workEvents.map(toMirrorEvent);
  const existingMirrors = phoneCalId
    ? listTaggedEvents(phoneCalId, cleanStart, syncEnd, CONFIG.PHONE_MIRROR_TAG_VALUE)
    : [];

  deltaSync(phoneCalId, existingMirrors, desiredMirrors, mirrorKey, budget, 'MIRROR');
}

/**
 * Real work events: upcoming, not our Busy blocks, not working-location banners,
 * and not declined.
 */
function isRealWorkEvent(item, now) {
  if (isManagedBusyItem(item)) return false;
  if (item.eventType === 'workingLocation') return false;
  if (selfResponse(item) === 'declined') return false;
  return eventDate(item.end) > now;
}

/**
 * Mirrors are identified by the signature stored on them at creation time.
 */
function mirrorKey(item) {
  return item.extendedProperties?.shared?.mirror_sig;
}

/**
 * Builds the Phone View copy of a work event, tagged with a signature of its core
 * fields so any title, time, or location change triggers a clean replacement.
 */
function toMirrorEvent(item) {
  const summary = item.summary || '(No title)';
  const location = item.location || '';
  const signature = `${item.id}_${busyKey(item)}_${summary}_${location}`;

  // Preserve conference link (Google Meet / Zoom) inside description so it's clickable on phone
  const meetUri = item.hangoutLink || item.conferenceData?.entryPoints?.find(e => e.entryPointType === 'video')?.uri;
  let description = item.description || '';
  if (meetUri && !description.includes(meetUri)) {
    description = `Video Call: ${meetUri}\n\n${description}`.trim();
  }

  return {
    summary: summary,
    description: description,
    location: location,
    start: item.start,
    end: item.end,
    reminders: { useDefault: false, overrides: [] }, // Avoid double notifications on phone
    extendedProperties: {
      shared: {
        [CONFIG.TAG_KEY]: CONFIG.PHONE_MIRROR_TAG_VALUE,
        mirror_sig: signature
      }
    }
  };
}

/**
 * Finds the secondary Phone View calendar by name, or returns null if missing.
 */
function findPhoneViewCalendarId() {
  let pageToken = null;
  do {
    const list = withRetry(() => Calendar.CalendarList.list({ pageToken: pageToken }));
    const match = list.items?.find(c => c.summary === CONFIG.PHONE_VIEW_CALENDAR_NAME);
    if (match) return match.id;
    pageToken = list.nextPageToken;
  } while (pageToken);

  return null;
}

/**
 * Creates the secondary Phone View calendar and returns its ID.
 */
function createPhoneViewCalendar() {
  Logger.log(`Creating new secondary calendar: "${CONFIG.PHONE_VIEW_CALENDAR_NAME}"...`);
  const createdCal = withRetry(() => Calendar.Calendars.insert({
    summary: CONFIG.PHONE_VIEW_CALENDAR_NAME,
    description: 'Clean mirror of real work events (excludes personal busy blocks) for mobile viewing.',
    timeZone: Session.getScriptTimeZone()
  }));
  Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
  return createdCal.id;
}

// ============================================================================
// PART 3: SHARED UTILITIES & HELPERS
// ============================================================================

/**
 * Acquires the script lock and runs `fn`, skipping if another run holds it.
 */
function withScriptLock(fn) {
  ensureAdvancedCalendarEnabled();

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) {
    Logger.log('Another sync operation is already running. Skipping.');
    return;
  }

  try {
    fn();
  } finally {
    lock.releaseLock();
  }
}

/**
 * Delta-syncs a calendar: keeps existing events whose key (via `keyOf`) is desired,
 * deletes the rest, then inserts any desired event resources still missing.
 */
function deltaSync(calendarId, existing, desired, keyOf, budget, label) {
  const desiredMap = new Map(desired.map(ev => [keyOf(ev), ev]));
  let kept = 0, deleted = 0, created = 0;

  // 1. Keep matches (first one wins, so duplicates get deleted), delete everything else
  for (const ev of existing) {
    if (desiredMap.delete(keyOf(ev))) {
      kept++;
      if (CONFIG.DRY_RUN) {
        Logger.log(`[KEEP ${label}]   ${describeEvent(ev)}`);
      }
      continue;
    }

    if (!tryWrite(budget, `[DELETE ${label}] ${describeEvent(ev)}`, () => Calendar.Events.remove(calendarId, ev.id))) break;
    deleted++;
  }

  // 2. Create whatever is still missing
  for (const ev of desiredMap.values()) {
    if (!tryWrite(budget, `[CREATE ${label}] ${describeEvent(ev)}`, () => Calendar.Events.insert(ev, calendarId))) break;
    created++;
  }

  const modePrefix = CONFIG.DRY_RUN ? '[DRY RUN] ' : '';
  Logger.log(`${modePrefix}${label} sync complete — Kept: ${kept}, Created: ${created}, Deleted: ${deleted}`);
}

/**
 * Performs a single calendar write while honoring DRY_RUN and the write budget.
 * Returns false once the budget is exhausted so callers can stop.
 */
function tryWrite(budget, logLine, fn) {
  if (CONFIG.DRY_RUN) {
    Logger.log(logLine);
    return true;
  }

  if (budget.remaining <= 0) {
    Logger.log(`Reached MAX_WRITES_PER_RUN (${CONFIG.MAX_WRITES_PER_RUN}). Remaining writes deferred to next run.`);
    return false;
  }

  withRetry(fn);
  Logger.log(logLine);
  budget.remaining--;
  Utilities.sleep(CONFIG.WRITE_SLEEP_MS);
  return true;
}

/**
 * Lists all non-cancelled single events overlapping [start, end], following pagination.
 */
function listEvents(calendarId, start, end, extraOptions = {}) {
  const items = [];
  let pageToken = null;

  do {
    const response = withRetry(() => Calendar.Events.list(calendarId, {
      ...extraOptions,
      timeMin: start.toISOString(),
      timeMax: end.toISOString(),
      singleEvents: true,
      maxResults: 250,
      pageToken: pageToken
    }));
    items.push(...(response.items || []).filter(item => item.status !== 'cancelled'));
    pageToken = response.nextPageToken;
  } while (pageToken);

  return items;
}

/**
 * Lists events tagged by this script (server-side `sharedExtendedProperty` filter).
 */
function listTaggedEvents(calendarId, start, end, tagValue) {
  return listEvents(calendarId, start, end, {
    sharedExtendedProperty: `${CONFIG.TAG_KEY}=${tagValue}`
  });
}

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

/**
 * The response status of the calendar this copy of the event lives on (if it's an attendee).
 */
function selfResponse(item) {
  return item.attendees?.find(a => a.self)?.responseStatus;
}

function addDays(date, days) {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function eventDate(time) {
  return new Date(time.dateTime || time.date);
}

function describeEvent(ev) {
  return `"${ev.summary || '(No title)'}" (${formatRange(eventDate(ev.start), eventDate(ev.end))})`;
}

function formatRange(start, end) {
  const tz = Session.getScriptTimeZone();
  const dayStr = Utilities.formatDate(start, tz, 'EEE, MMM d, yyyy');
  const startStr = Utilities.formatDate(start, tz, 'h:mm a');
  const endStr = Utilities.formatDate(end, tz, 'h:mm a');
  return `${dayStr}: ${startStr} - ${endStr}`;
}
