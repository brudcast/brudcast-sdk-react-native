import { BrudcastLog } from './log';

/** How long, in milliseconds, the SDK waits for a host handler before it uses the default. */
export const brudcastHandlerTimeout = 2000;

/**
 * Runs a host handler, answering `fallback` when it throws or does not answer within
 * `brudcastHandlerTimeout`, so a faulty handler never stalls a message, a notification or a link.
 *
 * @param name Names the handler in the warning logged on a fallback.
 * @param handler The host's handler.
 * @param fallback The answer used when the handler fails.
 * @returns The handler's answer, or the fallback.
 */
export async function runBrudcastHandler<T>(
  name: string,
  handler: () => T | Promise<T>,
  fallback: T
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<typeof timedOut>((resolve) => {
    timer = setTimeout(() => resolve(timedOut), brudcastHandlerTimeout);
  });
  try {
    const answer = await Promise.race([Promise.resolve().then(handler), timeout]);
    if (answer === timedOut) {
      BrudcastLog.warning(`The ${name} did not answer within two seconds; the default is used`);
      return fallback;
    }
    return answer as T;
  } catch (error) {
    BrudcastLog.error(`The ${name} threw: ${String(error)}`);
    return fallback;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Runs a call to the native SDK, logging instead of throwing when it fails, so no SDK call throws
 * into the app.
 *
 * @param name Names the call in the log.
 * @param call The call.
 * @returns The call's result, or undefined when it failed.
 */
export async function guardBrudcastCall<T>(
  name: string,
  call: () => T | Promise<T>
): Promise<T | undefined> {
  try {
    return await call();
  } catch (error) {
    BrudcastLog.error(`${name} failed: ${String(error)}`);
    return undefined;
  }
}

const timedOut: unique symbol = Symbol('timedOut');
