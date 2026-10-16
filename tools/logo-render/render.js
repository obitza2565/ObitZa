const sharp = require("sharp");
const path = require("path");

const src = path.join(__dirname, "..", "..", "exchange", "obz-token.svg");
const out = path.join(__dirname, "..", "..", "exchange", "obz-token.png");

sharp(src, { density: 300 })
  .resize(512, 512)
  .png()
  .toFile(out)
  .then(() => console.log("PNG_OK", out))
  .catch((err) => { console.error("PNG_FAIL", err.message); process.exit(1); });
