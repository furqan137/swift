/**
 * Theme Service — Local-time rotating day/night schedule.
 *
 * Schedule is computed in the caller's LOCAL timezone so every user sees
 * dark at night and light during the day regardless of where they are:
 *
 *   Slot 0 (00:00–06:00 local) → dark  (deep night)
 *   Slot 1 (06:00–12:00 local) → light (morning)
 *   Slot 2 (12:00–18:00 local) → light (afternoon)
 *   Slot 3 (18:00–24:00 local) → dark  (evening → night)
 *
 * Visible flips: 06:00 local (dark→light) and 18:00 local (light→dark).
 * The 12:00 and 00:00 boundaries still return a fresh snapshot so the
 * client's refresh timer stays on a 6-hour cadence.
 *
 * Pure function of the wall clock — no DB, no state. Client and server
 * share the same formula, so clients can compute locally if the backend
 * is unreachable.
 */

export type ThemeMode = 'light' | 'dark';

export interface ThemeSnapshot {
  mode: ThemeMode;
  slot: 0 | 1 | 2 | 3;
  phaseStartedAt: string;       // ISO 8601 UTC — when this phase began
  nextSwitchAt: string;         // ISO 8601 UTC — when the next slot boundary hits
  phaseDurationSeconds: number; // Always 21600 (6h) — explicit for clients
  serverTime: string;           // ISO 8601 UTC — authoritative "now"
  timeZone: string;             // IANA name actually used (echoed for debugging)
  localHour: number;            // 0..23 — what hour the user is currently in
}

const PHASE_HOURS = 6;
const PHASE_SECONDS = PHASE_HOURS * 60 * 60; // 21,600

class ThemeService {
  /**
   * Compute the current theme snapshot.
   *
   * @param tz   IANA timezone name (e.g. "America/New_York"). Falls back to
   *             UTC if missing or invalid so the endpoint never 500s on
   *             bad input.
   * @param now  Reference instant. Accepted for testability; defaults to
   *             `new Date()`.
   */
  getCurrent(tz?: string, now: Date = new Date()): ThemeSnapshot {
    const timeZone = this.validateTimeZone(tz);
    const local = this.getLocalParts(now, timeZone);

    // Which 6-hour slot does the LOCAL hour fall into?
    const slot = Math.floor(local.hour / PHASE_HOURS) as 0 | 1 | 2 | 3;

    // Dark bookends the day; light fills the middle. This matches natural
    // daylight rather than arbitrary UTC alternation.
    const mode: ThemeMode = slot === 1 || slot === 2 ? 'light' : 'dark';

    // Phase boundaries expressed as LOCAL wall clock, then converted to UTC
    // so the client can use them directly with a standard Date/Timer.
    const phaseStartHour = slot * PHASE_HOURS;
    const phaseEndHour = phaseStartHour + PHASE_HOURS;

    const phaseStartedUtc = this.zonedWallTimeToUtc(
      local.year, local.month, local.day,
      phaseStartHour, 0, 0,
      timeZone
    );

    // Slot 3 ends at 24:00 local, which is 00:00 the next day. We roll the
    // day over instead of passing hour=24 because not all tz libraries
    // accept it cleanly.
    const phaseEndUtc = phaseEndHour >= 24
      ? this.zonedWallTimeToUtc(
          local.year, local.month, local.day + 1,
          0, 0, 0,
          timeZone
        )
      : this.zonedWallTimeToUtc(
          local.year, local.month, local.day,
          phaseEndHour, 0, 0,
          timeZone
        );

    return {
      mode,
      slot,
      phaseStartedAt: phaseStartedUtc.toISOString(),
      nextSwitchAt: phaseEndUtc.toISOString(),
      phaseDurationSeconds: PHASE_SECONDS,
      serverTime: now.toISOString(),
      timeZone,
      localHour: local.hour,
    };
  }

  /**
   * Returns the input unchanged if it's a valid IANA timezone, otherwise
   * "UTC". `Intl.DateTimeFormat` throws `RangeError` on unknown zones.
   */
  private validateTimeZone(tz?: string): string {
    if (!tz) return 'UTC';
    try {
      // Instantiation is enough to validate — we don't keep the formatter.
      new Intl.DateTimeFormat('en-US', { timeZone: tz });
      return tz;
    } catch {
      return 'UTC';
    }
  }

  /**
   * Extract year/month/day/hour/minute/second for a UTC instant in the
   * caller's timezone. Uses `Intl.DateTimeFormat` (Node built-in) so no
   * extra dependency.
   */
  private getLocalParts(utcDate: Date, tz: string): {
    year: number; month: number; day: number;
    hour: number; minute: number; second: number;
  } {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hour12: false,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    const parts = fmt.formatToParts(utcDate);
    const get = (type: string): number => {
      const found = parts.find(p => p.type === type);
      return found ? parseInt(found.value, 10) : 0;
    };
    // Some locales/hour formats report "24" for midnight — normalize.
    let hour = get('hour');
    if (hour === 24) hour = 0;
    return {
      year: get('year'),
      month: get('month'),
      day: get('day'),
      hour,
      minute: get('minute'),
      second: get('second'),
    };
  }

  /**
   * Convert a local wall-clock time in a given timezone to the UTC Date
   * that renders as that wall clock. Handles DST transitions by
   * round-tripping through `Intl.DateTimeFormat` and correcting for the
   * observed offset.
   *
   * Not perfect during the "spring forward" gap hour (where the wall time
   * doesn't exist) — returns the post-jump UTC, which is acceptable for a
   * theme boundary.
   */
  private zonedWallTimeToUtc(
    year: number, month: number, day: number,
    hour: number, minute: number, second: number,
    tz: string
  ): Date {
    // Start by pretending the wall clock IS UTC. This is wrong by exactly
    // the timezone offset.
    const guessUtcMs = Date.UTC(year, month - 1, day, hour, minute, second);
    const guessDate = new Date(guessUtcMs);

    // See what that guess renders as in the target timezone.
    const seen = this.getLocalParts(guessDate, tz);
    const seenUtcMs = Date.UTC(
      seen.year, seen.month - 1, seen.day,
      seen.hour, seen.minute, seen.second
    );

    // The delta between what we wanted and what we got IS the offset for
    // that wall time (with DST correctly applied by the runtime).
    const offsetMs = seenUtcMs - guessUtcMs;

    return new Date(guessUtcMs - offsetMs);
  }
}

export const themeService = new ThemeService();
