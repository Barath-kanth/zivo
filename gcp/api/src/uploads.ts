import { Storage } from '@google-cloud/storage';
import { randomUUID } from 'crypto';
import { gcpProjectId } from './config.js';

const bucketName =
  process.env.GCS_BUCKET?.trim() ||
  (gcpProjectId ? `${gcpProjectId}-zivo-uploads` : '');

let storage: Storage | null = null;

function getStorage(): Storage {
  if (!storage) storage = new Storage({ projectId: gcpProjectId || undefined });
  return storage;
}

export function uploadsConfigured(): boolean {
  return Boolean(bucketName && gcpProjectId && gcpProjectId !== 'your-gcp-project-id');
}

/** Upload image bytes to GCS; return a time-limited signed read URL (free-tier safe). */
export async function uploadTaskPhoto(input: {
  bytes: Buffer;
  contentType?: string;
  userId: string;
}): Promise<{ url: string; path: string }> {
  if (!uploadsConfigured()) {
    throw new Error('GCS_BUCKET / GCP_PROJECT_ID not configured');
  }
  const ext =
    input.contentType?.includes('png')
      ? 'png'
      : input.contentType?.includes('webp')
        ? 'webp'
        : 'jpg';
  const path = `task-photos/${input.userId}/${Date.now()}_${randomUUID()}.${ext}`;
  const bucket = getStorage().bucket(bucketName);
  const file = bucket.file(path);
  await file.save(input.bytes, {
    contentType: input.contentType || 'image/jpeg',
    resumable: false,
    metadata: { cacheControl: 'public, max-age=86400' },
  });

  const [url] = await file.getSignedUrl({
    version: 'v4',
    action: 'read',
    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
  });
  return { url, path };
}
