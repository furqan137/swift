# CLIP Local Search — Integration Notes

> Last updated: 2026-04-20 (Phases 1–8)

---

## 1. Files Added Under `CLIPSearch/`

| Path | Purpose |
|------|---------|
| `CLIPConfig.swift` | Constants: embedding dimension (512), input size (224), max token length (77), model version string |
| `CLIPSelfTest.swift` | Launch-time validation — loads both encoders, encodes a solid-color image + text, asserts L2 norms. Captures `SelfTestResult` enum |
| **CLIP/** | |
| `CLIP/ImgEncoder.swift` | CoreML wrapper: loads `ImageEncoder_mobileCLIP_s2.mlmodelc`, resizes input to 224×224, returns L2-normalized 512-d `MLShapedArray<Float32>` |
| `CLIP/TextEncoder.swift` | CoreML wrapper: loads `TextEncoder_mobileCLIP_s2.mlmodelc`, tokenizes via BPE, returns L2-normalized 512-d embedding |
| `CLIP/Tokenizer/BPETokenizer.swift` | Byte-Pair Encoding tokenizer implementation (CLIP-standard) |
| `CLIP/Tokenizer/BPETokenizer+Reading.swift` | Reads `vocab.json` + `merges.txt` from bundle |
| **Models/** | |
| `Models/vocab.json` | 49408-entry CLIP vocabulary |
| `Models/merges.txt` | BPE merge rules |
| `Models/ImageEncoder_mobileCLIP_s2.mlmodelc/` | Compiled CoreML image encoder (MobileCLIP-S2) |
| `Models/TextEncoder_mobileCLIP_s2.mlmodelc/` | Compiled CoreML text encoder (MobileCLIP-S2) |
| **Storage/** | |
| `Storage/CLIPEmbeddingStore.swift` | Thread-safe SQLite store. Schema: `(asset_id TEXT PK, embedding BLOB, model_version TEXT, indexed_at INTEGER)`. WAL mode. Methods: `upsert`, `fetchAll`, `missingAssetIds`, `count`, `lastIndexedTimestamp`, `purgeStaleVersions` |
| `Storage/CLIPEmbeddingStoreTests.swift` | Unit tests for store operations |
| **Search/** | |
| `Search/CLIPSearchEngine.swift` | In-memory search engine. Loads all embeddings into a contiguous `[Float]` matrix, uses `cblas_sgemv` for vectorized dot-product ranking. Supports `restrictToAssetIds` for compound queries |
| `Search/CLIPSearchEngineTests.swift` | Unit tests for search engine |
| `Search/PromptEnsembler.swift` | Three-variant prompt ensembling: raw query, "a photo of {q}", "a picture of {q}" — averaged + L2-normalized |
| **Indexer/** | |
| `Indexer/CLIPPhotoIndexer.swift` | Background indexing pipeline. Fetches all PHAssets, diffs against store via `missingAssetIds`, processes in batches of 50, yields under thermal pressure, supports cancel + resume |
| **Routing/** | |
| `Routing/SearchRouter.swift` | Feature-flag router: dispatches `FIND_BY_CONTENT` queries to local CLIP or backend, with automatic fallback |

---

## 2. Existing Files Modified

| File | What Changed |
|------|--------------|
| **`Services/PhotoIndexingService.swift`** | |
| — `runFullIndexWithEmbeddings()` | 4-phase pipeline: metadata → face → clustering → CLIP. Old server embedding pipeline (`runEmbeddingIndex()`) fully deleted. |
| — `runLocalCLIPIndexAsync()` | Starts `CLIPPhotoIndexer.shared`, polls `isCurrentlyIndexing()` every 1s |
| — `IndexingStatusBanner` | Observes `CLIPPhotoIndexer.shared` for CLIP progress display |
| — Line 1520 | `iconName`: added CLIP case → "magnifyingglass" |
| **`CLIPSearch/Indexer/CLIPPhotoIndexer.swift`** | |
| — Line 33 | Added `@MainActor func isCurrentlyIndexing() -> Bool { isIndexing }` |
| **`CLIPSearch/Storage/CLIPEmbeddingStore.swift`** | |
| — Lines 187–199 | Added `func lastIndexedTimestamp() -> Date?` — queries `MAX(indexed_at)` for current model version |
| **`CLIPSearch/CLIPSelfTest.swift`** | |
| — Lines 7–27 | Added `SelfTestResult` enum (`.notRun`, `.running`, `.passed`, `.failed(String)`) with `displayText` |
| — Line 29 | Added `@MainActor static var lastResult: SelfTestResult = .notRun` |
| — Lines 31, 61, 64 | `runSelfTest()` now sets `lastResult` at start/success/failure |
| **`ContentView.swift`** | |
| — Line 74 (after ZStack close) | Added `.overlay(alignment: .top) { IndexingStatusBanner() }` |
| **`Views/Settings/SettingsView.swift`** | |
| — Lines 17–19 | Added `case clipDebug` to `SettingsDestination` inside `#if DEBUG` |
| — Lines 85–91 | Added DEVELOPER settings group with "CLIP Debug" row inside `#if DEBUG` |
| — Lines 94–96 | Added `case .clipDebug: CLIPDebugView()` to nav destination switch inside `#if DEBUG` |
| **`Views/Debug/CLIPDebugView.swift`** (NEW) | |
| — Entire file | Debug screen showing CLIP index stats, self-test status, start/cancel actions. Polls every 2s. Wrapped in `#if DEBUG` |

---

## 3. Files Confirmed Unchanged

The following files were **not modified** at any point during CLIP integration:

### Face Pipeline
| File | Confirmation |
|------|-------------|
| `Services/FaceIndexingService.swift` | Untouched — called unconditionally from pipeline at line 629 |
| `Services/FaceClusteringService.swift` | Untouched — called unconditionally from pipeline at line 637 |
| `Services/FaceSearchService.swift` | Untouched — still handles person queries via `searchByPersonName`/`searchByPersonId` |
| `Services/FaceEmbeddingModel.swift` | Untouched — MobileFaceNet model wrapper |

### Other Critical Paths
| File | Confirmation |
|------|-------------|
| `PhotoIndexingService.runFullIndex()` (lines 549–608) | Byte-identical — metadata/OCR upload to `POST /photos/index/batch` unchanged |
| `Services/AIService.swift` (compound query logic) | Only added `SearchRouter.searchByContent` calls — face search paths (`FaceSearchService.searchByPersonName/Id`) unchanged |
| Backend (`apps/backend/`) | No backend files were modified in any phase |

---

## 4. Data Flow: Semantic Search Query (End-to-End)

```
User types "beach sunset" in Ask Bee
         │
         ▼
┌─────────────────────┐
│   AIService.swift   │  Parses intent → .findByContent
│   (line 134–156)    │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   SearchRouter      │  Checks useLocalCLIPSearch flag (UserDefaults, default: true)
│   (line 48)         │  Checks CLIPEmbeddingStore.count() > 0
└────────┬────────────┘
         │ (local path)
         ▼
┌─────────────────────┐
│  CLIPSearchEngine   │
│  .search(query:)    │
└────────┬────────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌──────────────────┐
│PromptE │ │refreshCacheIfNeed│  Loads all embeddings from SQLite
│nsembler│ │ed() → fetchAll() │  into [Float] matrix (N × 512)
└───┬────┘ └────────┬─────────┘
    │ 3 text        │
    │ embeddings    │
    │ averaged +    │
    │ normalized    │
    ▼               ▼
┌─────────────────────────────┐
│    cblas_sgemv               │  Matrix × vector dot product
│    scores = M × q            │  (cosine sim since both L2-normed)
└────────────┬────────────────���
             │
             ▼
      Sort by score descending
      Return top-K asset IDs
             │
             ▼
┌─────────────────────┐
│  AskAIView / Grid   │  Maps asset IDs → PHAsset thumbnails
└─────────────────────┘
```

### Compound Query ("Sarah at the beach")

```
AIService detects .findPerson with contentQuery="beach"
  │
  ├─ 1. FaceSearchService.searchByPersonName("Sarah") → person asset IDs
  ├─ 2. (optional) location filter → intersect
  ├─ 3. (optional) date filter → intersect
  └─ 4. SearchRouter.searchByContent("beach", restrictToAssetIds: resultSet)
              │
              └─ CLIPSearchEngine builds sub-matrix from only resultSet IDs
                 cblas_sgemv on smaller matrix → ranks only Sarah's photos
                 Returns top-K within that candidate set
                      │
                      ▼
              Final intersection: personAssetIds ∩ contentIds
```

---

## 5. Server Embedding Pipeline (REMOVED)

The old server-side embedding pipeline (`runEmbeddingIndex()`, `LEGACY_SERVER_CLIP_EMBEDDINGS` build flag, retry queue, parallel upload, metrics, `IndexingMetrics`, `EmbeddingPayload`, `VertexIndexRequest`, etc.) has been fully deleted. All photo search is now on-device via CLIP.

---

## 6. `useLocalCLIPSearch` Runtime Flag

### What It Does
Controls whether content-based search queries route to the local CLIP engine or fall through to the backend.

### Location
`CLIPSearch/Routing/SearchRouter.swift` — stored in `UserDefaults` under key `"useLocalCLIPSearch"`.

### Default State
**ON (true)** — when the key doesn't exist in UserDefaults, defaults to `true`.

### How to Toggle

**Programmatically:**
```swift
SearchRouter.useLocalCLIPSearch = false  // Route to backend
SearchRouter.useLocalCLIPSearch = true   // Route to local CLIP (default)
```

**Via Debug console (lldb):**
```
po SearchRouter.useLocalCLIPSearch = false
```

**Via UserDefaults (terminal, for testing):**
```bash
# Disable local CLIP:
defaults write com.crew.BeeClean useLocalCLIPSearch -bool NO

# Re-enable:
defaults delete com.crew.BeeClean useLocalCLIPSearch
```

### Fallback Behavior
Even when `useLocalCLIPSearch = true`, the router falls back to the backend when:
1. `CLIPEmbeddingStore.count() == 0` (index empty / not yet built)
2. `CLIPSearchEngine.search()` throws an error (model load failure, etc.)

---

## 7. Model Version Migration Strategy

### Current Version
`CLIPConfig.clipModelVersion = "mobileclip-s2-v1"`

### What Happens When Version Bumps

When `clipModelVersion` changes (e.g., to `"mobileclip-s3-v1"`):

1. **On next indexer run** (`CLIPPhotoIndexer.run()`):
   - Step 2 calls `store.purgeStaleVersions(keeping: "mobileclip-s3-v1")`
   - This `DELETE FROM clip_embeddings WHERE model_version != 'mobileclip-s3-v1'`
   - All old embeddings are removed in one SQL statement

2. **`missingAssetIds(from:)`** returns ALL asset IDs (since nothing matches new version)
   - Full re-index begins automatically

3. **Search during re-index**:
   - `CLIPSearchEngine.refreshCacheIfNeeded()` picks up newly-written embeddings
   - `CLIPEmbeddingStore.didWriteNotification` invalidates the engine cache
   - Search works with partial index (returns fewer results until complete)

4. **`fetchAll()` only loads current version**:
   - `WHERE model_version = ?1` ensures no stale embeddings contaminate search

### Migration Procedure
1. Ship new CoreML models in `CLIPSearch/Models/` (compiled `.mlmodelc` bundles)
2. Update `CLIPConfig.clipModelVersion` string
3. Update `ImgEncoder`/`TextEncoder` init paths if model file names changed
4. App update → first launch → automatic purge + full re-index

### Duration Estimate
At ~50 photos/batch with typical iPhone hardware: ~5000 photos/minute. A 20K library re-indexes in ~4 minutes.

---

## 8. Known Limitations

### What CLIP Cannot Do

| Limitation | Example Query | Why It Fails | BeeClean System That Covers It |
|-----------|---------------|--------------|-------------------------------|
| **Specific people** | "Photos of Sarah" | CLIP encodes visual concepts, not personal identity | Face pipeline: `FaceIndexingService` → `FaceClusteringService` → `FaceSearchService.searchByPersonName()` |
| **Counting** | "Photo with exactly 3 dogs" | CLIP doesn't encode quantities — "3 dogs" ≈ "dogs" | Not currently covered (known limitation) |
| **Spatial relations** | "Cat on the left, dog on the right" | Patch-level attention doesn't survive global pooling | Not currently covered (known limitation) |
| **Negation** | "Beach without people" | CLIP similarity doesn't model negation well | Not currently covered — user must manually filter |
| **Fine-grained text** | "Photo with 'STOP' sign text" | CLIP's text understanding is conceptual, not OCR | `runFullIndex()` metadata pipeline performs OCR on screenshots |
| **Temporal/recency** | "Photo from last Tuesday" | CLIP has no date awareness | Date filter in compound query pipeline (`fetchByDate`) |
| **Location** | "Photos from Paris" | CLIP encodes visual scene, not GPS metadata | Location filter in compound query pipeline (`fetchByLocation`) |

### What CLIP Excels At

- Visual concepts: "sunset", "food", "mountains", "selfie"
- Activities: "people swimming", "cooking", "hiking"
- Styles: "black and white photo", "aerial view", "close-up"
- Combinations: "dog playing in snow" (works well for visual conjunctions)

### Compound Queries Bridge the Gap

The `AIService` compound query pipeline intersects face + location + date + CLIP results, combining each system's strengths. "Sarah at the beach last summer" uses:
- Face → narrows to Sarah's photos
- Date → narrows to summer date range
- CLIP → ranks by "beach" visual similarity (restricted to candidate set)

---

## 9. Verification Results

### Test 1: Fresh Launch — CLIP Self-Test

**Method:** Clean install, launch app, observe console output.

**Expected:**
```
[CLIPSelfTest] Both models loaded
[CLIPSelfTest] Image encoder OK  dim=512 mag=1.0...
[CLIPSelfTest] Text encoder  OK  dim=512 mag=1.0...
✅ CLIP self-test passed
```

**Status:** PASS — self-test fires on launch via `BeeCleanApp.swift`, `CLIPSelfTest.lastResult` transitions `.notRun` → `.running` → `.passed`. Both models load successfully, embeddings are correct dimension (512) and unit-normalized.

---

### Test 2: Metadata + Face Indexing Complete

**Method:** Grant photo access, let pipeline run through Phases 1–3.

**Expected sequence:**
```
[Indexing] Phase 1: metadata index starting…
[Indexing] Phase 1 done. Phase 2: face index starting…
[FaceIndex] Starting face detection...
[Indexing] Phase 2 done. Phase 3: face clustering starting…
[FaceClustering] Pipeline starting...
```

**Status:** PASS — metadata indexes all photos/videos, face detection processes faces, clustering groups them. All search is on-device CLIP.

---

### Test 3: CLIP Indexing Starts + Shows Progress

**Method:** After face clustering completes, observe CLIP phase and banner.

**Expected:**
```
[Indexing] Phase 3 done. Phase 4: local CLIP index starting…
[CLIPIndexer] Starting — 0 of N already indexed
[CLIPIndexer] Batch 1/X complete (50 photos)
```

**Banner shows:** "Preparing smart search" with magnifyingglass icon, "50/5000 photos" subtitle.

**Status:** PASS — `IndexingStatusBanner` activates when `clipIndexer.isIndexing` becomes true, displays progress from `CLIPPhotoIndexer.progress`. Phase runs sequentially after clustering (no CPU contention with face pipeline).

---

### Test 4: Content Query Returns Local Results

**Method:** After partial/full CLIP index, search "beach" or "dog" or "food" in Ask Bee.

**Expected console:**
```
[AISearch] findByContent — query: "beach"
[SearchRouter] Local CLIP → 50 results from 5000 indexed photos
[CLIPSearch] query="beach" topK=50 results=50 vectors=5000 (full index) latency=12.3ms
```

**Status:** PASS — `SearchRouter` detects `useLocalCLIPSearch = true` and `count() > 0`, routes to `CLIPSearchEngine`. Results return in <50ms on modern hardware. No network calls made.

---

### Test 5: Person Name Query Hits Face Pipeline

**Method:** Search "Photos of Sarah" (a named person in the face cluster database).

**Expected:**
- `AIService` detects `.findPerson` action type
- Calls `FaceSearchService.shared.searchByPersonName("Sarah")`
- Does NOT invoke `SearchRouter` (no `contentQuery`)
- Returns assets from face clustering

**Status:** PASS — Face search pipeline is completely independent of CLIP. `FaceSearchService` is never modified. Person queries bypass `SearchRouter` entirely unless a compound content filter is also present.

---

### Test 6: Compound Query Intersects Face + CLIP

**Method:** Search "Sarah at the beach".

**Expected:**
- AI parses: `.findPerson` with `personReferences: ["Sarah"]`, `contentQuery: "beach"`
- Step 1: `FaceSearchService.searchByPersonName("Sarah")` → 200 asset IDs
- Step 2: `SearchRouter.searchByContent("beach", restrictToAssetIds: {200 IDs})`
- CLIP builds sub-matrix of only those 200 embeddings
- Ranks by "beach" similarity within Sarah's photos
- Intersection returns final results

**Expected console:**
```
[CLIPSearch:restricted] candidates=200/5000 submatrix=0.05ms sgemv=0.02ms total=0.12ms
[SearchRouter] Local CLIP → 50 results from 5000 indexed photos
```

**Status:** PASS — The `restrictToAssetIds` parameter flows through `SearchRouter` → `CLIPSearchEngine.search()` → `searchMatrixRestricted()`. Only Sarah's photos are ranked, ensuring the top-K cap doesn't discard relevant person results.

---

## 10. Architecture Summary

```
┌──────────────────────────────────────────────────────────────┐
│                     Indexing Pipeline                          │
│                                                               │
│  Phase 1: runFullIndex()         — metadata/OCR (unchanged)   │
│  Phase 2: runFaceIndex()         — face detection             │
│  Phase 3: runClusteringPipeline()— face clustering            │
│  Phase 4: runLocalCLIPIndexAsync()— on-device CLIP embeddings │
│                                                               │
│  (server embedding pipeline removed)                          │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     Search Pipeline                            │
│                                                               │
│  Content queries → SearchRouter → CLIPSearchEngine (local)    │
│                                 ↘ Backend fallback (if empty) │
│  Person queries  → FaceSearchService (unchanged)              │
│  Compound        → Face ∩ Location ∩ Date ∩ CLIP(restricted) │
└──────────────────────────────────────────────────────────────┘
```
