import { Request } from 'express';

// User Types
export interface User {
  id: string;
  email: string;
  name?: string;
  picture?: string;
  google_id?: string;
  google_access_token?: string;
  google_refresh_token?: string;
  created_at: string;
  updated_at: string;
}

export interface JwtPayload {
  id: string;
  email: string;
  name?: string;
}

export interface AuthenticatedRequest extends Request {
  user?: JwtPayload;
}

// Google Types
export interface GoogleTokenPayload {
  sub: string;
  email: string;
  name?: string;
  picture?: string;
}

export interface GoogleCredentials {
  accessToken: string;
  refreshToken?: string;
}

// AI Types
export type AIActionType =
  | 'FIND_PERSON'
  | 'FIND_BY_DATE'
  | 'FIND_BY_LOCATION'
  | 'FIND_BY_CONTENT'
  | 'FIND_LARGEST'
  | 'FIND_DUPLICATES'
  | 'FIND_SCREENSHOTS'
  | 'CLEANUP_SUGGESTION'
  | 'INDEX_PHOTOS';

export interface AIAction {
  type: AIActionType;
  description: string;
  personName?: string;
  dateRange?: { start?: string; end?: string };
  location?: string;
  contentQuery?: string;
  mediaType?: 'photo' | 'video' | 'all';
  sortBy?: 'size' | 'date';
  limit?: number;
}

export interface AIChatRequest {
  message: string;
  conversationHistory?: AIConversationEntry[];
  context?: AIContextSummary;
}

export interface AIChatResponse {
  reply: string;
  actions: AIAction[];
}

export interface AIConversationEntry {
  role: 'user' | 'assistant';
  content: string;
}

export interface PersonContextEntry {
  name: string;
  relationship?: string;
  photoCount: number;
  lastSeenDate?: string;
  frequentLocations?: string[];
  coOccurringPeople?: string[];
}

export interface AIContextSummary {
  totalPhotos?: number;
  totalVideos?: number;
  totalScreenshots?: number;
  storageUsedMB?: number;
  knownPeople?: PersonContextEntry[];
  duplicateGroupsCount?: number;
  duplicateToCleanCount?: number;
  similarGroupsCount?: number;
  screenRecordingCount?: number;
  screenRecordingTotalBytes?: number;
  shortVideoCount?: number;
  shortVideoTotalBytes?: number;
  capabilities: AICapabilities;
}

export interface AICapabilities {
  canSearchByPerson: boolean;
  canSearchByDate: boolean;
  canSearchByLocation: boolean;
  canFindDuplicates: boolean;
  canFindLargeFiles: boolean;
}

// Photo Index Types
export interface PhotoAssetInput {
  assetId: string;
  createdAt: string;
  mediaType: 'photo' | 'video';
  isScreenshot?: boolean;
  byteSize?: number;
  duration?: number;
  lat?: number;
  lon?: number;
  ocrText?: string;
}

export interface PhotoQueryRequest {
  type: AIActionType;
  dateRange?: { start?: string; end?: string };
  contentQuery?: string;
  mediaType?: 'photo' | 'video' | 'all';
  limit?: number;
  lat?: number;
  lon?: number;
  radiusKm?: number;
}

export interface PhotoQueryResponse {
  assetIds: string[];
}

// Streak Types
export interface StreakData {
  currentStreak: number;
  bestStreak: number;
  lastActivityDate: string | null;
  lifetimeItemsCleaned: number;
  lifetimeBytesSaved: number;
  totalScansCompleted: number;
  cleanScore: number;
}

export interface StreakSyncRequest {
  currentStreak: number;
  bestStreak: number;
  lastActivityDate?: string | null;
  lifetimeItemsCleaned?: number;
  lifetimeBytesSaved?: number;
  totalScansCompleted?: number;
  cleanScore?: number;
}

export interface StreakActivityRequest {
  action: string;
  itemCount: number;
  bytesSaved?: number;
  metadata?: Record<string, unknown>;
}


