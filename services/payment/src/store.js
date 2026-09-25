/*
 * Tiny single-instance persistence adapter for the payment service.
 *
 * The demo originally kept orders, owner sessions and notifications in
 * in-memory Maps, so `docker compose down` wiped every order and receipt
 * reference. This adapter keeps the Maps as the in-memory source of truth
 * (no application rewrite) and mirrors them to a JSON file on a timer.
 *
 * Driver selection follows the same PERSISTENCE_DRIVER convention already used
 * by the product/catalog side of the project:
 *
 *   PERSISTENCE_DRIVER=local   (default) atomic JSON file under DATA_DIR
 *   PERSISTENCE_DRIVER=memory  previous behaviour, nothing is written
 *
 * Scope / limitations (documented, not hidden):
 *   - single instance only: two containers would clobber each other's file
 *   - rate-limit counters are deliberately NOT persisted (resetting them on
 *     restart is the safe direction)
 *   - writes are debounced (~1s) and flushed on SIGTERM/SIGINT, so a normal
 *     `docker compose stop` never loses data; a hard kill may lose <=1s
 */
const fs = require('fs');
const path = require('path');

const DRIVER = (process.env.PERSISTENCE_DRIVER || 'local').toLowerCase();
// Persistence is opt-in: it only activates when DATA_DIR points at a durable
// location (a bind mount in production). Without it the service behaves exactly
// like the original in-memory demo, which keeps the test suite side-effect free.
const DATA_DIR = (process.env.DATA_DIR || '').trim();
const STORE_FILE = DATA_DIR ? path.join(DATA_DIR, 'payment-store.json') : '';
const SAVE_INTERVAL_MS = 1000;

const enabled = () => DRIVER === 'local' && Boolean(DATA_DIR);

function atomicWrite(target, contents) {
  const dir = path.dirname(target);
  fs.mkdirSync(dir, { recursive: true, mode: 0o750 });
  const temporary = `${target}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, contents, { mode: 0o600 });
  fs.renameSync(temporary, target);
}

function serialize(maps) {
  return `${JSON.stringify({
    version: 1,
    savedAt: new Date().toISOString(),
    orders: Object.fromEntries(maps.orders),
    notifications: Object.fromEntries(maps.notifications),
    sessions: Object.fromEntries(maps.sessions)
  })}\n`;
}

/*
 * Rebuild the in-memory Maps from disk. Never throws: a missing file means a
 * fresh install, and a corrupt file is quarantined instead of crashing the
 * service on boot.
 */
function hydrate(maps, log = console) {
  if (!enabled()) return { loaded: false, reason: DATA_DIR ? 'driver=memory' : 'DATA_DIR not set' };

  let raw;
  try {
    raw = fs.readFileSync(STORE_FILE, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return { loaded: false, reason: 'no existing store' };
    log.warn(`Payment store unreadable (${error.code}); starting empty`);
    return { loaded: false, reason: error.code };
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    // Quarantine rather than delete so the data can be recovered by hand.
    const quarantine = `${STORE_FILE}.corrupt-${Date.now()}`;
    try {
      fs.renameSync(STORE_FILE, quarantine);
      log.warn(`Payment store was not valid JSON; moved to ${quarantine}`);
    } catch {
      log.warn('Payment store was not valid JSON and could not be quarantined');
    }
    return { loaded: false, reason: 'corrupt' };
  }

  const now = Date.now();
  let orders = 0;
  let notifications = 0;
  let sessions = 0;

  for (const [key, value] of Object.entries(parsed.orders || {})) {
    if (value && typeof value === 'object' && key) {
      maps.orders.set(key, value);
      orders += 1;
    }
  }
  for (const [key, value] of Object.entries(parsed.notifications || {})) {
    if (value && typeof value === 'object' && key) {
      maps.notifications.set(key, value);
      notifications += 1;
    }
  }
  for (const [key, value] of Object.entries(parsed.sessions || {})) {
    // Expired sessions are dropped instead of being restored.
    if (value && typeof value === 'object' && value.expiresAt > now) {
      maps.sessions.set(key, value);
      sessions += 1;
    }
  }

  return { loaded: true, orders, notifications, sessions };
}

/*
 * Start mirroring. Returns a handle with flush() for a final synchronous save
 * and stop() to clear the timer (used by the tests).
 */
function attach(maps, log = console) {
  const handle = {
    driver: DRIVER,
    file: STORE_FILE,
    enabled: enabled(),
    lastSaved: '',
    saves: 0,
    failures: 0
  };

  if (!enabled()) {
    const reason = DRIVER !== 'local' ? `PERSISTENCE_DRIVER=${DRIVER}` : 'DATA_DIR is not set';
    log.info(`Payment persistence disabled (${reason})`);
    // Keep the handle shape identical to the enabled path so callers never
    // need to feature-detect before calling flush()/stop().
    handle.flush = () => false;
    handle.stop = () => {};
    return handle;
  }

  // Fail soft: if the directory is not writable (for example a root-owned
  // bind mount), run in-memory rather than taking the service down.
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true, mode: 0o750 });
  } catch (error) {
    handle.enabled = false;
    log.warn(`Payment persistence disabled, ${DATA_DIR} is not writable (${error.code})`);
    return handle;
  }

  handle.flush = () => {
    if (!handle.enabled) return false;
    try {
      const payload = serialize(maps);
      if (payload === handle.lastSaved) return false;
      atomicWrite(STORE_FILE, payload);
      handle.lastSaved = payload;
      handle.saves += 1;
      return true;
    } catch (error) {
      handle.failures += 1;
      log.warn(`Payment store save failed (${error.code || error.message})`);
      return false;
    }
  };

  const timer = setInterval(handle.flush, SAVE_INTERVAL_MS);
  // Never keep the Node.js event loop alive just for the persistence timer.
  if (typeof timer.unref === 'function') timer.unref();

  handle.stop = () => clearInterval(timer);

  const shutdown = signal => {
    log.info(`Flushing payment store on ${signal}`);
    handle.flush();
    handle.stop();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  log.info(`Payment persistence active at ${STORE_FILE}`);
  return handle;
}

module.exports = { attach, hydrate, serialize, enabled, STORE_FILE, DATA_DIR, DRIVER };
