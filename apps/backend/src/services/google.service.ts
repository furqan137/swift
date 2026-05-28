import { OAuth2Client } from 'google-auth-library';
import { config } from '../config/index.js';
import { GoogleTokenPayload } from '../types/index.js';

class GoogleService {
  private oauth2Client: OAuth2Client;

  constructor() {
    this.oauth2Client = new OAuth2Client(
      config.google.clientId,
      config.google.clientSecret,
      config.google.redirectUri
    );
  }

  generateAuthUrl(state?: string): string {
    return this.oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: config.google.scopes,
      prompt: 'consent',
      state
    });
  }

  async verifyIdToken(idToken: string): Promise<GoogleTokenPayload | null> {
    const audience = [config.google.clientId, config.google.iosClientId].filter(Boolean) as string[];
    try {
      const ticket = await this.oauth2Client.verifyIdToken({
        idToken,
        audience
      });
      const payload = ticket.getPayload();

      if (!payload) {
        console.error('[verifyIdToken] No payload in verified ticket');
        return null;
      }

      return {
        sub: payload.sub!,
        email: payload.email!,
        name: payload.name,
        picture: payload.picture
      };
    } catch (error) {
      // Detailed diagnostics. The single most common production failure
      // here is an audience mismatch — iOS idTokens are issued for the
      // iOS OAuth client, and if `GOOGLE_IOS_CLIENT_ID` is missing on the
      // server, our audience whitelist contains only the web client and
      // every iOS sign-in fails. Logging the token's actual audience next
      // to the whitelist makes that mismatch visible in one log line
      // instead of a generic "Error verifying ID token."
      const tokenAud = decodeJwtAudience(idToken);
      console.error('[verifyIdToken] Failed', {
        whitelistedAudiences: audience,
        tokenAudience: tokenAud,
        audienceMatches: tokenAud ? audience.includes(tokenAud) : null,
        error: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
  }

  async exchangeCodeForTokens(code: string) {
    const { tokens } = await this.oauth2Client.getToken(code);
    return tokens;
  }
}

export const googleService = new GoogleService();

/// Best-effort decode of a JWT's `aud` claim. The token is base64url-encoded
/// JSON with three segments — we only need the middle one. Pure read; we
/// don't trust the result for anything but logging.
function decodeJwtAudience(idToken: string): string | null {
  try {
    const parts = idToken.split('.');
    if (parts.length !== 3) return null;
    const payload = parts[1];
    const padded = payload.replace(/-/g, '+').replace(/_/g, '/').padEnd(payload.length + (4 - payload.length % 4) % 4, '=');
    const decoded = JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
    return typeof decoded.aud === 'string' ? decoded.aud : null;
  } catch {
    return null;
  }
}
