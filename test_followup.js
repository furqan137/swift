const jwt = require('jsonwebtoken');

const JWT_SECRET = 'be9053d73dc4b83d20f32f81f926c6dd1f9b61ba0e5670e73633c82d74ba10adb90e804068fe90f03c480c7a58c43133ca38e610d1880cbefd31a5a29c19b435';

// Create a test token
const token = jwt.sign(
  { userId: 'test-user-123', email: 'test@example.com' },
  JWT_SECRET,
  { expiresIn: '1h' }
);

async function testScenario11() {
  console.log('=== Scenario 11: "show me flowers" → "which is your favorite" ===\n');

  // First request: "show me flowers" (photoSearch)
  console.log('1. First query: "show me flowers"');
  const response1 = await fetch('http://localhost:3001/ai/personality', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify({
      userQuery: 'show me flowers',
      intent: 'photoSearch'
    })
  });

  const result1 = await response1.json();
  console.log('Response:', JSON.stringify(result1, null, 2));
  console.log('');

  // Second request: "which is your favorite" (followUp with context)
  console.log('2. Follow-up: "which is your favorite"');
  console.log('   Context: previous query + previous reply');
  const response2 = await fetch('http://localhost:3001/ai/personality', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify({
      userQuery: 'which is your favorite',
      intent: 'followUp',
      context: {
        previousUserQuery: 'show me flowers',
        previousBeeReply: result1.reply
      }
    })
  });

  const result2 = await response2.json();
  console.log('Response:', JSON.stringify(result2, null, 2));
  console.log('');

  console.log('=== Analysis ===');
  console.log('If Bee gives a specific opinion (e.g., "the purple one"), the prompt is BROKEN.');
  console.log('If Bee says something like "I wish I could pick!", the prompt is CORRECT.');
}

testScenario11().catch(console.error);
