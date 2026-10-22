# memmini Shared Memory

## How to search it

memmini is the shared memory MCP that every agent on this host writes to. It holds session observations, summaries, and saved lessons.

1. **User's wording first.** Call `memory_smart_search` with the user's question as they phrased it. Then retry with the key symbol, file name, and feature name.
2. **Expand hits.** Use `memory_recall` or `memory_timeline` on a hit to read the surrounding session.
3. **Lessons.** Use `memory_lesson_recall` for saved decisions and gotchas on the topic.

## Common pitfalls

- **Agent memory is not ground truth.** A session note records what an agent believed then. Cross-check it against the code anchor and say so when it disagrees.
- **Fabricated IDs.** Cite only session IDs and observation IDs the tools returned. Never invent one.
- **Unavailable server.** If the memmini MCP is not connected, stop and report the gap.
