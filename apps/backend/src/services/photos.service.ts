import { supabaseService } from './supabase.service.js';
import { PhotoAssetInput, PhotoQueryRequest, PhotoQueryResponse, AIActionType } from '../types/index.js';

class PhotosService {
  async indexBatch(userId: string, assets: PhotoAssetInput[]): Promise<{ indexed: number }> {
    const db = supabaseService.getAdminClient();

    // Upsert photo_assets
    const rows = assets.map(a => ({
      user_id: userId,
      asset_id: a.assetId,
      created_at: a.createdAt,
      media_type: a.mediaType,
      is_screenshot: a.isScreenshot ?? false,
      byte_size: a.byteSize ?? null,
      duration: a.duration ?? null,
      lat: a.lat ?? null,
      lon: a.lon ?? null,
    }));

    const { error: assetError } = await db
      .from('photo_assets')
      .upsert(rows, { onConflict: 'user_id,asset_id' });

    if (assetError) {
      console.error('Error upserting photo_assets:', assetError);
      throw new Error('Failed to index photo assets');
    }

    // Upsert photo_ocr for assets that have OCR text
    const ocrRows = assets
      .filter(a => a.ocrText && a.ocrText.trim().length > 0)
      .map(a => ({
        user_id: userId,
        asset_id: a.assetId,
        text: a.ocrText!.trim(),
      }));

    if (ocrRows.length > 0) {
      const { error: ocrError } = await db
        .from('photo_ocr')
        .upsert(ocrRows, { onConflict: 'user_id,asset_id' });

      if (ocrError) {
        console.error('Error upserting photo_ocr:', ocrError);
        throw new Error('Failed to index OCR data');
      }
    }

    return { indexed: assets.length };
  }

  async query(userId: string, request: PhotoQueryRequest): Promise<PhotoQueryResponse> {
    const db = supabaseService.getAdminClient();
    const limit = request.limit ?? 50;

    switch (request.type) {
      case 'FIND_LARGEST': {
        let q = db
          .from('photo_assets')
          .select('asset_id')
          .eq('user_id', userId)
          .not('byte_size', 'is', null)
          .order('byte_size', { ascending: false })
          .limit(limit);

        if (request.mediaType && request.mediaType !== 'all') {
          q = q.eq('media_type', request.mediaType);
        }

        const { data, error } = await q;
        if (error) throw new Error(`FIND_LARGEST query failed: ${error.message}`);
        return { assetIds: (data || []).map(r => r.asset_id) };
      }

      case 'FIND_SCREENSHOTS': {
        const { data, error } = await db
          .from('photo_assets')
          .select('asset_id')
          .eq('user_id', userId)
          .eq('is_screenshot', true)
          .order('created_at', { ascending: false })
          .limit(limit);

        if (error) throw new Error(`FIND_SCREENSHOTS query failed: ${error.message}`);
        return { assetIds: (data || []).map(r => r.asset_id) };
      }

      case 'FIND_BY_DATE': {
        let q = db
          .from('photo_assets')
          .select('asset_id')
          .eq('user_id', userId)
          .order('created_at', { ascending: false })
          .limit(limit);

        if (request.dateRange?.start) {
          q = q.gte('created_at', request.dateRange.start);
        }
        if (request.dateRange?.end) {
          q = q.lte('created_at', request.dateRange.end);
        }
        if (request.mediaType && request.mediaType !== 'all') {
          q = q.eq('media_type', request.mediaType);
        }

        const { data, error } = await q;
        if (error) throw new Error(`FIND_BY_DATE query failed: ${error.message}`);
        return { assetIds: (data || []).map(r => r.asset_id) };
      }

      case 'FIND_BY_LOCATION': {
        if (request.lat == null || request.lon == null) {
          return { assetIds: [] };
        }

        const radiusKm = request.radiusKm ?? 10;
        // Approximate degree offset for bounding box
        const latDelta = radiusKm / 111;
        const lonDelta = radiusKm / (111 * Math.cos((request.lat * Math.PI) / 180));

        const { data, error } = await db
          .from('photo_assets')
          .select('asset_id')
          .eq('user_id', userId)
          .not('lat', 'is', null)
          .gte('lat', request.lat - latDelta)
          .lte('lat', request.lat + latDelta)
          .gte('lon', request.lon - lonDelta)
          .lte('lon', request.lon + lonDelta)
          .order('created_at', { ascending: false })
          .limit(limit);

        if (error) throw new Error(`FIND_BY_LOCATION query failed: ${error.message}`);
        return { assetIds: (data || []).map(r => r.asset_id) };
      }

      case 'FIND_BY_CONTENT': {
        if (!request.contentQuery) {
          return { assetIds: [] };
        }

        // OCR text search
        const { data, error } = await db
          .from('photo_ocr')
          .select('asset_id')
          .eq('user_id', userId)
          .ilike('text', `%${request.contentQuery}%`)
          .limit(limit);

        if (error) throw new Error(`FIND_BY_CONTENT query failed: ${error.message}`);
        return { assetIds: (data || []).map(r => r.asset_id) };
      }

      default: {
        // Surface unsupported filter types instead of silently returning [],
        // so the caller can distinguish "no matches" from "feature missing".
        const unknownType: string = (request as { type?: string }).type ?? 'undefined';
        console.warn(`[photos/query] Unsupported filter type: ${unknownType}`);
        return { assetIds: [] };
      }
    }
  }

}

export const photosService = new PhotosService();
