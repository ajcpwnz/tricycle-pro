---
name: ste-short
description: Short ASD-STE100 for persisted prose. Use before you write anything that outlives the chat - docs, README, spec, commit message, PR body, ticket, comment in a tracker, rules file. Not for code or chat replies.
---

# Short STE

People and agents read persisted prose later, with no chance to ask what you
meant. Write it in short Simplified Technical English (ASD-STE100):

1. Lead with the point. No preamble, no recap, no closing offer.
2. One fact per sentence. 20 words at most for steps, 25 for descriptions.
3. Active voice, simple tenses, imperative for steps.
4. Full sentences. Keep the subject, the verb and the articles. No fragments,
   even when the chat runs in caveman mode.
5. One word for one thing, for the whole text.
6. Plain verbs. No phrasal verbs (`spin up`, `set up`), no nominalizations
   (`perform an analysis`), no marketing words (`robust`, `seamless`), no
   semicolons.
7. Keep every hedge, number, negation and identifier exact. `May have failed`
   stays `may have failed`.
8. Use a list for three or more items or steps. State each fact once.

Code blocks, inline code, commands, paths and quoted errors stay as they are.

Write it right in the first draft. When you have the asd-ste100 plugin, the
style gate lints this prose. It does not block. It names the flagged sentences,
and you fix each one with one small Edit. Commit messages are not gated.
