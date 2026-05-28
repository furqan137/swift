import { Router } from 'express';
import { signPromotionalOffer } from '../controllers/subscriptions.controller.js';

const router = Router();

// POST /subscriptions/sign-promo-offer
//
// Body: { productID, offerID, applicationUsername? }
// Returns: { keyIdentifier, nonce, timestamp, signature }
//
// iOS calls this when the user taps "Claim your offer" on PromoPaywallView.
// Signature is single-use (Apple validates nonce uniqueness server-side).
router.post('/sign-promo-offer', signPromotionalOffer);

export default router;
