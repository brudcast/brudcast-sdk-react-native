/** What the backend returns at sign-in, ready for `Brudcast.identify`. */
export type SignedIn = {
  externalId: string;
  userHash: string;
  email?: string;
};

/**
 * The app's own backend, which signs users in and holds what the app must never contain: the
 * identity secret and the Brudcast API key. The README lists the endpoints it needs.
 */
export class SampleBackend {
  /**
   * Talks to the backend at a URL, such as `http://10.0.2.2:4000` for one on the host.
   *
   * @param baseUrl The backend's URL.
   */
  constructor(readonly baseUrl: string) {}

  /**
   * Signs a user in. The backend computes the user hash with the identity secret.
   *
   * @param userId The user's id in the app.
   * @param email The user's email.
   * @returns The id and hash to identify with.
   */
  async login(userId: string, email: string | undefined): Promise<SignedIn> {
    const response = await this.post('/login', { userId, email });
    return {
      externalId: String(response.externalId),
      userHash: String(response.userHash),
      ...(typeof response.email === 'string' ? { email: response.email } : {}),
    };
  }

  /**
   * Asks the backend to send the user a welcome in-app message through the Brudcast API.
   *
   * @param externalId The user's id.
   */
  async sendWelcome(externalId: string): Promise<void> {
    await this.post('/welcome', { externalId });
  }

  /**
   * Posts JSON and reads JSON back.
   *
   * @param path The endpoint.
   * @param body The request body.
   * @returns The response body.
   * @throws {Error} With the backend's `message` when it answers with an error status.
   */
  private async post(path: string, body: object): Promise<Record<string, unknown>> {
    const response = await fetch(this.baseUrl.replace(/\/+$/, '') + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    const decoded = text.trim() === '' ? {} : (JSON.parse(text) as Record<string, unknown>);
    if (!response.ok) {
      throw new Error(
        typeof decoded.message === 'string' ? decoded.message : `HTTP ${response.status}`
      );
    }
    return decoded;
  }
}
