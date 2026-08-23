// Lightweight Lua sanity check: balance of function/end, if/end, do/end,
// and paren/brace/bracket counts. Not a real parser; catches gross mistakes.
const fs = require("fs");
const path = require("path");

const files = process.argv.slice(2);
let hadError = false;

for (const f of files) {
  const src = fs.readFileSync(f, "utf8");

  // Strip long comments --[[ ... ]] and line comments -- ... first, and strings.
  let stripped = src
    .replace(/--\[\[[\s\S]*?\]\]/g, "")   // long comments
    .replace(/--[^\n]*/g, "")              // line comments
    .replace(/"(?:\\.|[^"\\])*"/g, '""')   // double-quoted strings
    .replace(/'(?:\\.|[^'\\])*'/g, "''")   // single-quoted strings
    .replace(/\[\[[\s\S]*?\]\]/g, "[[]]"); // long strings

  const counts = {
    paren: 0, brace: 0, bracket: 0,
    blockOpen: 0, // function/if/for/while/do/repeat
    end: 0, until: 0,
  };

  for (const ch of stripped) {
    if (ch === "(") counts.paren++;
    else if (ch === ")") counts.paren--;
    else if (ch === "{") counts.brace++;
    else if (ch === "}") counts.brace--;
    else if (ch === "[") counts.bracket++;
    else if (ch === "]") counts.bracket--;
  }

  // Count keywords (word-boundary-ish)
  const kw = (w) => (stripped.match(new RegExp("(^|[^%w_])" + w + "([^%w_]|$)".replace(/%w/g,"\\w"), "g")) || []).length;
  // simpler:
  const kwCount = (w) => {
    const re = new RegExp("(?:^|[^A-Za-z0-9_])" + w + "(?:[^A-Za-z0-9_]|$)", "g");
    return (stripped.match(re) || []).length;
  };
  const funcs   = kwCount("function");
  const ifs     = kwCount("if");
  const elseifs = kwCount("elseif");
  const fors    = kwCount("for");
  const whiles  = kwCount("while");
  const dos     = kwCount("do");   // includes 'do' inside 'for x do' / 'while x do'
  const repeats = kwCount("repeat");
  const ends    = kwCount("end");
  const untils  = kwCount("until");

  // Blocks needing 'end': function, if, for-do, while-do, standalone do
  // 'for' and 'while' share their 'do' with themselves; a bare 'do ... end' also uses one 'do'.
  // So expected ends = function + if + for + while + (do - for - while) [standalone do]
  //                  = function + if + for + while + max(0, do - for - while)
  const standaloneDos = Math.max(0, dos - fors - whiles);
  // Each 'if' chain uses one 'end'; 'elseif' reuses parent's 'end'.
  // But kwCount("if") also matches 'elseif' via word boundaries? No: word
  // boundary is [^A-Za-z0-9_], and 'elseif' has 'e' before 'if', which IS
  // alphanumeric, so 'if' inside 'elseif' is NOT matched. Good.
  const expectedEnds = funcs + ifs + fors + whiles + standaloneDos;

  const rel = path.basename(f);
  const problems = [];
  if (counts.paren !== 0)   problems.push(`paren balance ${counts.paren}`);
  if (counts.brace !== 0)   problems.push(`brace balance ${counts.brace}`);
  if (counts.bracket !== 0) problems.push(`bracket balance ${counts.bracket}`);
  if (ends !== expectedEnds) problems.push(`end mismatch: got ${ends}, expected ${expectedEnds} (fn=${funcs} if=${ifs} for=${fors} while=${whiles} do_std=${standaloneDos})`);
  if (repeats !== untils)   problems.push(`repeat/until mismatch: ${repeats}/${untils}`);

  if (problems.length) {
    console.log(`[FAIL] ${rel}: ${problems.join("; ")}`);
    hadError = true;
  } else {
    console.log(`[ ok ] ${rel}: paren=0 brace=0 bracket=0 end=${ends}=expected`);
  }
}

process.exit(hadError ? 1 : 0);
