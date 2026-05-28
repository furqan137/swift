import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { config } from '../config/index.js';
import { User, GoogleCredentials } from '../types/index.js';

class SupabaseService {
  private adminClient: SupabaseClient;

  constructor() {
    this.adminClient = createClient(
      config.supabase.url,
      config.supabase.serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    );
  }

  getAdminClient(): SupabaseClient {
    return this.adminClient;
  }

  async findUserByEmail(email: string): Promise<User | null> {
    const { data, error } = await this.adminClient
      .from('users')
      .select('*')
      .eq('email', email)
      .single();

    if (error || !data) return null;
    return data as User;
  }

  async findUserById(id: string): Promise<User | null> {
    const { data, error } = await this.adminClient
      .from('users')
      .select('*')
      .eq('id', id)
      .single();

    if (error || !data) return null;
    return data as User;
  }

  async createUser(userData: Partial<User>): Promise<User | null> {
    const { data, error } = await this.adminClient
      .from('users')
      .insert({
        ...userData,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      })
      .select()
      .single();

    if (error) {
      console.error('Error creating user:', error);
      return null;
    }
    return data as User;
  }

  async updateUser(id: string, updates: Partial<User>): Promise<boolean> {
    const { error } = await this.adminClient
      .from('users')
      .update({
        ...updates,
        updated_at: new Date().toISOString()
      })
      .eq('id', id);

    return !error;
  }

  async getGoogleCredentials(userId: string): Promise<GoogleCredentials | null> {
    const { data, error } = await this.adminClient
      .from('users')
      .select('google_access_token, google_refresh_token')
      .eq('id', userId)
      .single();

    if (error || !data) return null;

    return {
      accessToken: data.google_access_token,
      refreshToken: data.google_refresh_token
    };
  }
}

export const supabaseService = new SupabaseService();
