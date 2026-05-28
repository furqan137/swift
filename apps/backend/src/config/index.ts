import dotenv from 'dotenv';

dotenv.config();

export const config = {
  // Server
  port: parseInt(process.env.PORT || '3001', 10),
  nodeEnv: process.env.NODE_ENV || 'development',

  // JWT
  jwtSecret: process.env.JWT_SECRET!,
  jwtExpiresIn: '7d',

  // Google OAuth
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID!,
    iosClientId: process.env.GOOGLE_IOS_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    redirectUri: process.env.GOOGLE_REDIRECT_URI!,
    scopes: [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.modify',
      'https://www.googleapis.com/auth/gmail.labels'
    ] as string[]
  },

  // Supabase
  supabase: {
    url: process.env.SUPABASE_URL!,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY!
  },

};

// Validate required environment variables
export const validateConfig = () => {
  const required = [
    'JWT_SECRET',
    'GOOGLE_CLIENT_ID',
    // GOOGLE_IOS_CLIENT_ID is required because every iOS sign-in carries
    // an idToken signed by the iOS OAuth client. `verifyIdToken` whitelists
    // both the web and iOS audiences via `[clientId, iosClientId].filter(Boolean)`.
    // If GOOGLE_IOS_CLIENT_ID is unset, that filter drops it and the audience
    // whitelist contains only the web client. Every iOS idToken then fails
    // the audience check, the controller returns 400 "Invalid Google token",
    // and the user is silently kicked back to "Connect your Inbox" with a
    // generic auth-failed message. Failing fast on boot beats silent
    // post-deploy auth outages.
    'GOOGLE_IOS_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GOOGLE_REDIRECT_URI',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY',
  ];

  const missing = required.filter(key => !process.env[key]);

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }
};
