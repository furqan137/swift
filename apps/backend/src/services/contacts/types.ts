export interface LookupResult {
  valid: boolean | null;
  carrier: string | null;
  lineType: string | null;
  location: string | null;
  countryCode: string | null;
  countryName: string | null;
  internationalFormat: string | null;
  cached: boolean;
  note?: string;
}

export interface StatsSummary {
  totalMerged: number;
  totalDeleted: number;
  totalExported: number;
  totalBackups: number;
  totalRestored: number;
  recentActions: {
    action: string;
    contactCount: number;
    createdAt: string;
  }[];
}

export interface BackupMetadata {
  id: string;
  contactCount: number;
  createdAt: string;
}
