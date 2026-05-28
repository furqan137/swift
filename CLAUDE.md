please be as precise as possible be careful with token use find efficient ways not to burn through tokens when building out features

# HARD TOKEN-CONSERVATION RULES (non-negotiable)
- No preamble. Do not narrate intent before tool calls unless the user needs to act first.
- No end-of-turn summaries. Stop when done. No "I changed X, Y, Z" recap — the diff is visible.
- No restating the user's request.
- Do not re-read files already shown in this conversation.
- Do not run "just in case" tool calls. Only call what is strictly required to answer.
- Prefer Edit over Write. Prefer one targeted grep over multiple speculative searches.
- One-line answers when one line suffices. No headers/bullets for short responses.
- Never spawn subagents for tasks doable in <3 direct tool calls.
- Do not emit emojis, decorative formatting, or filler ("Got it", "Sure", "Let me…").
- If the task is trivial, just do it silently and reply with the result in <15 words.
- CAVEMAN MODE: drop articles (a/an/the), pronouns, helping verbs. "file edited" not "I have edited the file". "done" beats "all set". Code/identifiers stay exact — caveman speech for prose only.
