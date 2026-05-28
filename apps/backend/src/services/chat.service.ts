import { supabaseService } from './supabase.service.js';

export interface ChatSessionDTO {
  id: string;
  title: string;
  messages: unknown[];
  isPinned: boolean;
  createdAt: string;
  updatedAt: string;
}

interface UpsertInput {
  userId: string;
  id: string;
  title: string;
  messages: unknown[];
  isPinned: boolean;
}

class ChatService {
  async listSessions(userId: string): Promise<ChatSessionDTO[]> {
    const db = supabaseService.getAdminClient();

    const { data, error } = await db
      .from('chat_sessions')
      .select('id, title, messages, is_pinned, created_at, updated_at')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });

    if (error) {
      console.error('[chat] List error:', error.message);
      throw new Error('Failed to fetch chat sessions');
    }

    return (data || []).map(row => ({
      id: row.id,
      title: row.title,
      messages: Array.isArray(row.messages) ? row.messages : [],
      isPinned: row.is_pinned,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));
  }

  async upsertSession(input: UpsertInput): Promise<ChatSessionDTO> {
    const db = supabaseService.getAdminClient();

    const row = {
      id: input.id,
      user_id: input.userId,
      title: input.title,
      messages: input.messages,
      is_pinned: input.isPinned,
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await db
      .from('chat_sessions')
      .upsert(row, { onConflict: 'id' })
      .select('id, title, messages, is_pinned, created_at, updated_at')
      .single();

    if (error) {
      console.error('[chat] Upsert error:', error.message);
      throw new Error('Failed to save chat session');
    }

    return {
      id: data.id,
      title: data.title,
      messages: Array.isArray(data.messages) ? data.messages : [],
      isPinned: data.is_pinned,
      createdAt: data.created_at,
      updatedAt: data.updated_at,
    };
  }

  async deleteSession(userId: string, id: string): Promise<void> {
    const db = supabaseService.getAdminClient();

    const { error } = await db
      .from('chat_sessions')
      .delete()
      .eq('user_id', userId)
      .eq('id', id);

    if (error) {
      console.error('[chat] Delete error:', error.message);
      throw new Error('Failed to delete chat session');
    }
  }
}

export const chatService = new ChatService();
