import { BrudcastLog } from './log';

/** A value an event property may hold. */
export type BrudcastPropertyValue = string | number | boolean | null;

/** Event properties. */
export type BrudcastProperties = Readonly<Record<string, BrudcastPropertyValue>>;

/**
 * Keeps the property values the Brudcast API accepts: strings, finite numbers, booleans and nulls.
 * Anything else is dropped with a warning before it crosses to native.
 *
 * @param properties The properties the app passed.
 * @returns The properties that may cross.
 */
export function brudcastProperties(
  properties: Readonly<Record<string, unknown>>
): Record<string, BrudcastPropertyValue> {
  const accepted: Record<string, BrudcastPropertyValue> = {};
  for (const [key, value] of Object.entries(properties)) {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') {
      accepted[key] = value;
    } else if (typeof value === 'number') {
      if (Number.isFinite(value)) {
        accepted[key] = value;
      } else {
        BrudcastLog.warning(
          `Property "${key}" is ${value}, which JSON cannot carry; it is dropped`
        );
      }
    } else {
      BrudcastLog.warning(
        `Property "${key}" is ${describe(value)}, not a string, number, boolean or null; it is dropped`
      );
    }
  }
  return accepted;
}

/**
 * Names a value's type for a warning.
 *
 * @param value The value.
 * @returns A short description, such as `an object` or `undefined`.
 */
function describe(value: unknown): string {
  if (value === undefined) return 'undefined';
  if (Array.isArray(value)) return 'an array';
  if (value instanceof Date) return 'a Date';
  return `a ${typeof value}`;
}
