import jwt from 'jsonwebtoken';
import { config } from '../config/index.js';
import { googleService } from './google.service.js';
import { supabaseService } from './supabase.service.js';
import { JwtPayload, GoogleTokenPayload } from '../types/index.js';

interface AuthResult {
  token: string;
  userId: string;
  isNewUser: boolean;
  user: {
    id: string;
    email: string;
    name?: string;
    picture?: string;
  };
}

class AuthService {
  generateToken(payload: JwtPayload): string {
    return jwt.sign(payload, config.jwtSecret, {
      expiresIn: '7d'
    });
  }

  verifyToken(token: string): JwtPayload | null {
    try {
      return jwt.verify(token, config.jwtSecret) as JwtPayload;
    } catch {
      return null;
    }
  }

  getGoogleAuthUrl(state?: string): string {
    return googleService.generateAuthUrl(state);
  }

  async handleGoogleCallback(code: string): Promise<AuthResult | null> {
    const tokens = await googleService.exchangeCodeForTokens(code);

    if (!tokens.id_token) return null;

    const payload = await googleService.verifyIdToken(tokens.id_token);
    if (!payload || !payload.email) return null;

    return this.processGoogleAuth(payload, tokens.access_token, tokens.refresh_token);
  }

  async handleIOSGoogleAuth(idToken: string, accessToken?: string): Promise<AuthResult | null> {
    const payload = await googleService.verifyIdToken(idToken);
    if (!payload || !payload.email) return null;

    return this.processGoogleAuth(payload, accessToken);
  }

  private async processGoogleAuth(
    payload: GoogleTokenPayload,
    accessToken?: string | null,
    refreshToken?: string | null
  ): Promise<AuthResult | null> {
    const existingUser = await supabaseService.findUserByEmail(payload.email);

    let userId: string;
    let isNewUser = false;

    if (existingUser) {
      userId = existingUser.id;
      await supabaseService.updateUser(userId, {
        name: payload.name,
        picture: payload.picture,
        google_access_token: accessToken || existingUser.google_access_token,
        google_refresh_token: refreshToken || existingUser.google_refresh_token
      });
    } else {
      isNewUser = true;
      const newUser = await supabaseService.createUser({
        email: payload.email,
        name: payload.name,
        picture: payload.picture,
        google_id: payload.sub,
        google_access_token: accessToken || undefined,
        google_refresh_token: refreshToken || undefined
      });

      if (!newUser) {
        // Race condition: another request created this user between our
        // findUserByEmail and createUser calls. Retry the lookup.
        const raceUser = await supabaseService.findUserByEmail(payload.email);
        if (!raceUser) return null;
        userId = raceUser.id;
        isNewUser = false;
        await supabaseService.updateUser(userId, {
          name: payload.name,
          picture: payload.picture,
          google_access_token: accessToken || raceUser.google_access_token,
          google_refresh_token: refreshToken || raceUser.google_refresh_token
        });
      } else {
        userId = newUser.id;
      }
    }

    const token = this.generateToken({
      id: userId,
      email: payload.email,
      name: payload.name
    });

    return {
      token,
      userId,
      isNewUser,
      user: {
        id: userId,
        email: payload.email,
        name: payload.name,
        picture: payload.picture
      }
    };
  }

  async updateName(userId: string, name: string): Promise<boolean> {
    return supabaseService.updateUser(userId, { name });
  }

  async updateGoogleToken(userId: string, accessToken: string): Promise<boolean> {
    return supabaseService.updateUser(userId, {
      google_access_token: accessToken
    });
  }

  async getCurrentUser(userId: string) {
    const user = await supabaseService.findUserById(userId);
    if (!user) return null;

    return {
      id: user.id,
      email: user.email,
      name: user.name,
      picture: user.picture,
      created_at: user.created_at
    };
  }
}

export const authService = new AuthService();
