# Cubicraftia Profanity Word Lists

## Attribution

Word lists derived from LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words,
licensed under Creative Commons Attribution 4.0 International (CC-BY-4.0).
Copyright Shutterstock, Inc.
https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words

The LDNOOBW project is the authoritative source. These files are a curated subset:
- False positives for gaming context have been removed (e.g., terms that are normal
  gameplay vocabulary such as "kill", "die", "gun", "shoot", "fight").
- Dutch (NL) list is curated from the LDNOOBW NL file and supplemented with
  commonly used offensive terms not covered by the upstream list.

## Files

| File                  | Language | Min words | License  |
|-----------------------|----------|-----------|----------|
| `wordlist_en.txt`     | English  | 50+       | CC-BY-4.0 |
| `wordlist_nl.txt`     | Dutch    | 30+       | CC-BY-4.0 |

Additional languages (FR, ES, DE) can be added by contributors following the same
pattern (see Contributing below). They are not required for v1 store submission.

## Format

- One word or phrase per line, lowercase.
- Lines beginning with `#` are comments and are skipped by the filter at runtime.
- Blank lines are skipped.
- No trailing whitespace.

## How the Filter Uses These Files

`ProfanityFilter.load_word_lists()` reads `wordlist_en.txt` and `wordlist_nl.txt` at
startup via `FileAccess.open("res://assets/profanity/wordlist_{lang}.txt")`. Each list
is compiled into a separate `RegEx` object (`_regex_en`, `_regex_nl`) to stay under the
~500-word regex alternation limit that causes performance degradation on mobile (Tier-3
Android). The two regexes are applied in sequence by `filter()` and `filter_reject()`.

- `filter(text)` — replaces matches with `[filtered]`. Used for chat relay.
- `filter_reject(text)` — returns `true` if any word matches. Used for username,
  world name, and avatar name validation. Callers show "Please choose another name."
  and never echo the rejected input.

## Contributing

To add or remove words:

1. Edit the relevant `wordlist_<lang>.txt` file.
2. Keep entries lowercase, one per line.
3. Prefix comment lines with `#`.
4. Do not exceed 500 content lines per file (regex engine performance limit on mobile).
5. If adding a new language, create `wordlist_<iso639-1>.txt` following the same format.
6. Submit a PR. Changes are reviewed for false positives before merging.

For gaming context review: terms that describe normal game mechanics (combat, items, etc.)
should not be blocked. When in doubt, err on the side of inclusion — a false rejection
("please choose another name") is less harmful than a false pass.
