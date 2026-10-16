/* eslint-disable @typescript-eslint/no-require-imports -- Standalone CommonJS Node artwork generator. */
// Run from web: node scripts/generate-editorial-artwork.cjs
// Derive social and browser artwork from the same bundled fonts and app capture.
const { ImageResponse } = require("next/og");
const { createElement: el } = require("react");
const fs = require("node:fs/promises");
const path = require("node:path");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");

async function regularOutlines(filename) {
  const font = await fs.readFile(path.join(root, "app/fonts", filename));
  // Satori cannot read these variable fonts' fvar metadata. Use their default
  // Regular outlines for static artwork; the browser receives the full fonts.
  // An unknown table is ignored by OpenType readers. No font file is modified.
  for (let n = 0; n < font.readUInt16BE(4); n++) {
    const offset = 12 + n * 16;
    if (font.toString("ascii", offset, offset + 4) === "fvar") {
      font.write("_var", offset, 4, "ascii");
    }
  }
  return font;
}

async function main() {
  const [editorial, sans, css, screen] = await Promise.all([
    regularOutlines("Newsreader.ttf"), regularOutlines("DMSans.ttf"),
    fs.readFile(path.join(root, "app/globals.css"), "utf8"),
    fs.readFile(path.join(root, "public/app/editorial-plan-current.png")),
  ]);
  const token = name => {
    const value = css.match(new RegExp(`--${name}:\\s*(#[0-9A-Fa-f]{6})`))?.[1];
    if (!value) throw new Error(`Missing Editorial token: ${name}`);
    return value;
  };
  const fonts = [
    { name: "Editorial", data: editorial, weight: 400, style: "normal" },
    { name: "Sans", data: sans, weight: 400, style: "normal" },
  ];
  // ImageResponse's image reader accepts PNG, not the website's WebP assets.
  const screenPng = await sharp(screen).png().toBuffer();
  const render = async (tree, width, height) => Buffer.from(await new ImageResponse(tree, { width, height, fonts }).arrayBuffer());
  const icon = async size => render(el("div", { style: {
    display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center",
    background: token("canvas"), color: token("ink"), fontFamily: "Editorial", fontSize: size * .84,
  } }, "P"), size, size);
  const [small, apple] = await Promise.all([icon(64), icon(180)]);
  const ico = Buffer.alloc(22);
  ico.writeUInt16LE(1, 2); ico.writeUInt16LE(1, 4);
  ico[6] = 64; ico[7] = 64;
  ico.writeUInt16LE(1, 10); ico.writeUInt16LE(32, 12);
  ico.writeUInt32LE(small.length, 14); ico.writeUInt32LE(22, 18);
  const artwork = await render(el("div", { style: {
    display: "flex", width: "100%", height: "100%", background: token("canvas"),
    color: token("ink"), padding: "54px 64px", fontFamily: "Sans", justifyContent: "space-between",
  } },
    el("div", { style: { display: "flex", flexDirection: "column", width: 650 } },
      el("div", { style: { fontFamily: "Editorial", fontSize: 42 } }, "Plated"),
      el("div", { style: { display: "flex", flexDirection: "column", marginTop: 65, fontFamily: "Editorial", fontSize: 100, lineHeight: 1 } },
        el("div", null, "Your week,"), el("div", null, "well fed.")),
      el("div", { style: { marginTop: 34, fontSize: 24, color: token("ink-secondary") } }, "Bring your recipes, your people, and the week together."),
      el("div", { style: { marginTop: "auto", fontSize: 18, color: token("olive") } }, "plated.food")),
    el("img", { src: `data:image/png;base64,${screenPng.toString("base64")}`, width: 240, height: 522, style: { borderRadius: 12, border: `1px solid ${token("hairline")}` } })), 1200, 630);
  await Promise.all([
    fs.writeFile(path.join(root, "app/icon.png"), small),
    fs.writeFile(path.join(root, "app/apple-icon.png"), apple),
    fs.writeFile(path.join(root, "app/favicon.ico"), Buffer.concat([ico, small])),
    fs.writeFile(path.join(root, "app/opengraph-image.png"), artwork),
  ]);
  console.log("Generated Editorial browser and sharing artwork.");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
