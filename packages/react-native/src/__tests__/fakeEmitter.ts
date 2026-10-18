/**
 * A stand-in for a codegen event emitter on a mocked native module: it records listeners, and
 * `emit` calls them the way native would.
 *
 * @returns The emitter, callable like the generated one, with `emit` and `listenerCount`.
 */
export function fakeEmitter<T>() {
  const listeners = new Set<(value: T) => void>();
  const emitter = (listener: (value: T) => void) => {
    listeners.add(listener);
    return {
      remove() {
        listeners.delete(listener);
      },
    };
  };
  return Object.assign(emitter, {
    emit(value: T): void {
      listeners.forEach((listener) => listener(value));
    },
    listenerCount(): number {
      return listeners.size;
    },
  });
}

/**
 * Lets pending promise callbacks run.
 */
export async function flushPromises(): Promise<void> {
  for (let i = 0; i < 5; i++) {
    await Promise.resolve();
  }
}
