const PASSWORD_KEYWORDS = "password|passwd|passwort|kennwort|passphrase|passcode|contrase\u00f1a|contrasenya|mot de passe|senha|wachtwoord|parola|parool|has\u0142o|heslo|jelsz\u00f3|l\u00f6senord|salasana|\u043f\u0430\u0440\u043e\u043b\u044c|\u5bc6\u7801|\u30d1\u30b9\u30ef\u30fc\u30c9|\uc554\ud638";

const PASSWORD_PROMPT_REGEX = new RegExp(
  "^(?:[^$#%>\\r\\n]{0,120})?(?:" + PASSWORD_KEYWORDS + ")(?:[^:\uFF1A?\\r\\n]{0,80})?[:\uFF1A?]\\s*$",
  "iu"
);

export const MAX_PASSWORD_PHRASE_LENGTH = 100;
export const MIN_PASSWORD_PHRASE_LENGTH = 2;
export const MAX_PASSWORD_PHRASES = 10000;

const takeLast = (s, n) => Array.from(s).slice(-n).join("");

const normalizePhraseKey = (value) => {
  let s = String(value).trim();
  if (s.normalize) s = s.normalize("NFKC");
  return s.toLowerCase();
};

export const stripTerminalNoise = (value) => {
  if (value === null || value === undefined) return "";
  let s = String(value);
  if (s.length === 0) return "";
  if (s.normalize) s = s.normalize("NFKC");
  s = s.replace(/\x1b\]8;;.*?\x1b\\/g, "");
  s = s.replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "");
  s = s.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
  s = s.replace(/\x1b[()][0-9A-B]/g, "");
  s = s.replace(/\x1b[78=><A-Za-z]/g, "");
  s = s.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
  s = s.replace(/[\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\u061c\ufeff\u00ad]/g, "");
  s = s.replace(/[\ue000-\uf8ff]/g, "");
  s = s.replace(/[\u{F0000}-\u{FFFFD}\u{100000}-\u{10FFFD}]/gu, "");
  s = s.replace(/\u00a0/g, " ");
  return s;
};

export const normalizePasswordPhrases = (value) => {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const trimmed = item.trim();
    const length = Array.from(trimmed).length;
    if (length < MIN_PASSWORD_PHRASE_LENGTH || length > MAX_PASSWORD_PHRASE_LENGTH) continue;
    if (stripTerminalNoise(trimmed).trim().length === 0) continue;
    const key = normalizePhraseKey(trimmed);
    if (key.length === 0) continue;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(trimmed);
    if (out.length >= MAX_PASSWORD_PHRASES) break;
  }
  return out;
};

export const compilePasswordPhrases = (value) => {
  const list = normalizePasswordPhrases(value);
  const compiled = [];
  for (const phrase of list) {
    let s = phrase.trim();
    if (s.normalize) s = s.normalize("NFKC");
    s = s.toLowerCase();
    if (s.length === 0) continue;
    compiled.push(s);
  }
  return compiled;
};

export const updatePromptLine = (prev, chunk) => {
  const cleaned = stripTerminalNoise(chunk);
  return takeLast(((prev || "") + cleaned).split(/[\r\n]/).pop(), 256);
};

export const readTerminalPromptLine = (term) => {
  try {
    const buf = term?.buffer?.active;
    if (!buf) return "";
    const base = typeof buf.baseY === "number" ? buf.baseY : 0;
    const cursor = base + (buf.cursorY || 0);
    const total = typeof buf.length === "number" ? buf.length : null;
    for (let d = 0; d < 3; d++) {
      const end = total === null ? cursor - d : Math.min(cursor - d, total - 1);
      let start = end;
      if (start < 0) continue;
      while (start > 0) {
        let prevLine = null;
        try {
          prevLine = buf.getLine(start);
        } catch {
          break;
        }
        if (!prevLine || !prevLine.isWrapped) break;
        start -= 1;
      }
      let logical = "";
      for (let y = start; y <= end; y++) {
        let lineObj = null;
        try {
          lineObj = buf.getLine(y);
        } catch {
          break;
        }
        if (!lineObj) break;
        logical += lineObj.translateToString(true);
      }
      if (logical.trim().length === 0) continue;
      return takeLast(stripTerminalNoise(logical), 256);
    }
    return "";
  } catch {
    return "";
  }
};

export const isPasswordPrompt = (line, customPhrases) => {
  if (line === null || line === undefined) return false;
  const cleaned = stripTerminalNoise(line);
  if (cleaned.trim().length === 0) return false;
  const rows = cleaned.split(/[\r\n]/);
  let target = "";
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i].trim().length > 0) {
      target = rows[i];
      break;
    }
  }
  if (target.length === 0) return false;
  target = takeLast(target, 256);
  if (PASSWORD_PROMPT_REGEX.test(target)) return true;
  if (!Array.isArray(customPhrases) || customPhrases.length === 0) return false;
  let lower = target;
  if (lower.normalize) lower = lower.normalize("NFKC");
  lower = lower.toLowerCase();
  for (const entry of customPhrases) {
    if (typeof entry !== "string") continue;
    const trimmed = entry.trim();
    const length = Array.from(trimmed).length;
    if (length < MIN_PASSWORD_PHRASE_LENGTH || length > MAX_PASSWORD_PHRASE_LENGTH) continue;
    if (stripTerminalNoise(trimmed).trim().length === 0) continue;
    let needle = trimmed;
    if (needle.normalize) needle = needle.normalize("NFKC");
    needle = needle.toLowerCase();
    if (needle.length === 0) continue;
    if (lower.includes(needle)) return true;
  }
  return false;
};

export const isPasswordPromptWithCompiled = (line, compiledPhrases) => {
  if (line === null || line === undefined) return false;
  const cleaned = stripTerminalNoise(line);
  if (cleaned.trim().length === 0) return false;
  const rows = cleaned.split(/[\r\n]/);
  let target = "";
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i].trim().length > 0) {
      target = rows[i];
      break;
    }
  }
  if (target.length === 0) return false;
  target = takeLast(target, 256);
  if (PASSWORD_PROMPT_REGEX.test(target)) return true;
  if (!Array.isArray(compiledPhrases) || compiledPhrases.length === 0) return false;
  let lower = target;
  if (lower.normalize) lower = lower.normalize("NFKC");
  lower = lower.toLowerCase();
  for (const needle of compiledPhrases) {
    if (typeof needle !== "string" || needle.length === 0) continue;
    if (lower.includes(needle)) return true;
  }
  return false;
};
