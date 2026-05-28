import type { Request, Response } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';

// MARK: - Sign Promotional Offer
//
// Generates an ECDSA-P256 signature for Apple's StoreKit Promotional Offer
// flow. The iOS app calls this endpoint before invoking
// `Product.purchase(options: [.promotionalOffer(...)])` so Apple's payment
// sheet applies the discounted price ($31.99 first year) instead of the
// regular price ($79.99).
//
// Apple's signature payload format (joined by U+2063 INVISIBLE SEPARATOR):
//   appBundleID | keyIdentifier | productIdentifier | offerIdentifier
//   | applicationUsername | nonce | timestamp
//
// Signature: ECDSA over SHA-256, output in IEEE P1363 (r||s) format, then
// base64 for transport over HTTP. iOS base64-decodes and passes to StoreKit.
//
// SECURITY: the private key (.p8 file contents) lives in APPLE_PROMO_PRIVATE_KEY.
// Never log it. Never return it. Never embed it in the iOS app.

const APPLE_BUNDLE_ID = 'com.beeclean.app';
const APPLE_KEY_ID = '6H8LAMH9XB';
const ZERO_WIDTH_SEPARATOR = '⁣';

const requestSchema = z.object({
    productID: z.string().min(1),
    offerID: z.string().min(1),
    // Opaque user identifier — passed back in the signed payload so Apple
    // can tie the offer to a specific user account. For freshly-onboarding
    // users with no account, the client sends a stable device UUID.
    applicationUsername: z.string().optional(),
});

export async function signPromotionalOffer(req: Request, res: Response) {
    try {
        const parsed = requestSchema.safeParse(req.body);
        if (!parsed.success) {
            return res.status(400).json({
                error: 'invalid_request',
                details: parsed.error.issues,
            });
        }

        const { productID, offerID, applicationUsername = '' } = parsed.data;

        const privateKeyPEM = process.env.APPLE_PROMO_PRIVATE_KEY;
        if (!privateKeyPEM) {
            console.error('[sign-promo-offer] APPLE_PROMO_PRIVATE_KEY env var missing');
            return res.status(500).json({ error: 'server_misconfigured' });
        }

        // Apple requires a unique nonce per signature. Lowercase UUID per docs.
        const nonce = crypto.randomUUID().toLowerCase();
        // Timestamp in milliseconds since epoch. Apple validates this is recent
        // (within ~24h), so don't cache signatures.
        const timestamp = Date.now();

        // Build the canonical payload Apple expects. Order is fixed.
        const payload = [
            APPLE_BUNDLE_ID,
            APPLE_KEY_ID,
            productID,
            offerID,
            applicationUsername,
            nonce,
            String(timestamp),
        ].join(ZERO_WIDTH_SEPARATOR);

        // Load the ECDSA P-256 key from PEM. The .p8 file Apple gives you is
        // already PEM-encoded (BEGIN PRIVATE KEY ... END PRIVATE KEY).
        const privateKey = crypto.createPrivateKey({
            key: privateKeyPEM,
            format: 'pem',
        });

        // Sign with ECDSA-SHA256 in IEEE P1363 format (raw r||s, 64 bytes).
        // Apple does NOT accept DER-encoded signatures here.
        const signer = crypto.createSign('SHA256');
        signer.update(payload);
        signer.end();
        const signatureBuffer = signer.sign({
            key: privateKey,
            dsaEncoding: 'ieee-p1363',
        });

        const signatureBase64 = signatureBuffer.toString('base64');

        return res.json({
            keyIdentifier: APPLE_KEY_ID,
            nonce,
            timestamp,
            signature: signatureBase64,
        });
    } catch (error) {
        const message = error instanceof Error ? error.message : 'unknown_error';
        console.error('[sign-promo-offer] sign failed:', message);
        return res.status(500).json({ error: 'sign_failed' });
    }
}
