const PASSWORD_KEYWORDS = "password|passwd|passwort|kennwort|passphrase|passcode|contrase\u00f1a|contrasenya|mot de passe|senha|wachtwoord|parola|parool|has\u0142o|heslo|jelsz\u00f3|l\u00f6senord|salasana|\u043f\u0430\u0440\u043e\u043b\u044c|\u5bc6\u7801|\u30d1\u30b9\u30ef\u30fc\u30c9|\uc554\ud638";

const PASSWORD_PROMPT_REGEX = new RegExp(
  "^(?:[^$#%>\\r\\n]{0,120})?(?:" + PASSWORD_KEYWORDS + ")(?:[^:\uFF1A?\\r\\n]{0,80})?[:\uFF1A?]\\s*$",
  "iu"
);

const takeLast = (s, n) => Array.from(s).slice(-n).join("");

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

export const compilePasswordPromptPattern = (source) => {
  if (source instanceof RegExp) {
    const base = String(source.flags || "").replace(/[^dimsuvy]/g, "").replace(/g/g, "");
    const withI = base.includes("i") ? base : base + "i";
    try {
      return new RegExp(source.source, withI);
    } catch {
      try {
        return new RegExp(source.source, "i");
      } catch {
        return null;
      }
    }
  }
  if (typeof source !== "string") return null;
  const text = source.trim();
  if (text.length === 0) return null;
  if (text.length > 500) return null;
  try {
    return new RegExp(text, "iu");
  } catch {
    return null;
  }
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

export const isPasswordPrompt = (line, customPattern) => {
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
  const custom = compilePasswordPromptPattern(customPattern);
  if (custom) {
    try {
      custom.lastIndex = 0;
      const hit = custom.test(target);
      custom.lastIndex = 0;
      if (hit) return true;
    } catch {
      return PASSWORD_PROMPT_REGEX.test(target);
    }
  } else if (typeof customPattern === "string" && customPattern.trim().length > 0) {
    return PASSWORD_PROMPT_REGEX.test(target);
  }
  return PASSWORD_PROMPT_REGEX.test(target);
};
