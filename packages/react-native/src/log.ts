import type { BrudcastLogLevel } from './options';

const order: readonly BrudcastLogLevel[] = ['verbose', 'debug', 'info', 'warning', 'error', 'none'];

let threshold: BrudcastLogLevel = 'warning';

/**
 * Logs from the JavaScript side of the SDK at the level given to `initialize`. The native SDKs
 * log to Logcat and the unified log themselves.
 */
export const BrudcastLog = {
  /**
   * Sets the lowest level that is logged.
   *
   * @param level The level.
   */
  setLevel(level: BrudcastLogLevel): void {
    threshold = level;
  },

  /**
   * Logs a debug message.
   *
   * @param message The message.
   */
  debug(message: string): void {
    write('debug', message);
  },

  /**
   * Logs a warning.
   *
   * @param message The message.
   */
  warning(message: string): void {
    write('warning', message);
  },

  /**
   * Logs an error.
   *
   * @param message The message.
   */
  error(message: string): void {
    write('error', message);
  },
};

/**
 * Writes a message to the console when its level reaches the threshold.
 *
 * @param level The message's level.
 * @param message The message.
 */
function write(level: BrudcastLogLevel, message: string): void {
  if (threshold === 'none' || order.indexOf(level) < order.indexOf(threshold)) return;
  const line = `[Brudcast] ${message}`;
  if (level === 'error') {
    console.error(line);
  } else if (level === 'warning') {
    console.warn(line);
  } else {
    console.log(line);
  }
}
