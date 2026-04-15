'use strict';

// normalize-pr-ref.js — Pure function to normalize a PR reference to a positive integer.
//
// Accepts:
//   - Bare number: "42"
//   - Hash-prefixed: "#42"
//   - Full GitHub PR URL: "https://github.com/<owner>/<repo>/pull/42"
//
// Returns:
//   { ok: true, number: <positive integer> }
//   { ok: false, error: <string> }

const GITHUB_PR_URL = /^https?:\/\/github\.com\/[^/]+\/[^/]+\/pull\/(\d+)(?:[/?#].*)?$/;

function normalizePrRef(input) {
  if (typeof input !== 'string') {
    return { ok: false, error: `expected PR number, got ${JSON.stringify(input)}` };
  }

  const trimmed = input.trim();
  if (trimmed === '') {
    return { ok: false, error: 'expected PR number, got ""' };
  }

  let candidate = trimmed;

  const urlMatch = trimmed.match(GITHUB_PR_URL);
  if (urlMatch) {
    candidate = urlMatch[1];
  } else if (candidate[0] === '#') {
    candidate = candidate.slice(1);
  }

  if (!/^\d+$/.test(candidate)) {
    return { ok: false, error: `expected PR number, got "${input}"` };
  }

  const number = Number.parseInt(candidate, 10);
  if (!Number.isFinite(number) || number <= 0) {
    return { ok: false, error: `expected PR number, got "${input}"` };
  }

  return { ok: true, number };
}

module.exports = { normalizePrRef };
