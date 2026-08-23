// Real Lua parse via luaparse.
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const files = process.argv.slice(2);
let bad = false;
for (const f of files) {
  const src = fs.readFileSync(f, "utf8");
  try {
    luaparse.parse(src, { luaVersion: "5.1" });
    console.log(`[ ok ] ${path.basename(f)}`);
  } catch (e) {
    bad = true;
    console.log(`[FAIL] ${path.basename(f)}: ${e.message}`);
  }
}
process.exit(bad ? 1 : 0);
