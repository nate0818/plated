/* eslint-disable @typescript-eslint/no-require-imports -- Node test harness uses CommonJS. */
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");
const captures = require("../app/components/productCaptures.json");

test("iPad marketing captures match the native app's supported orientations", async () => {
  const project = fs.readFileSync(path.join(__dirname, "../../Plated.xcodeproj/project.pbxproj"), "utf8");
  const configurations = [...project.matchAll(/INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad\s*=\s*"([^"]+)"/g)];
  assert.ok(configurations.length > 0, "The native iPad orientation declarations must be present");
  const capture = captures.ipad;
  const metadata = await sharp(path.join(__dirname, "../public", capture.src)).metadata();
  const displayed = metadata.autoOrient;
  const orientation = displayed.width > displayed.height ? "landscape" : "portrait";
  assert.equal(orientation, capture.orientation);
  for (const [, orientations] of configurations) {
    assert.ok(orientations.includes(orientation === "landscape" ? "UIInterfaceOrientationLandscape" : "UIInterfaceOrientationPortrait"), `${orientation} marketing imagery is not supported by this iPad build configuration`);
  }
  assert.equal(metadata.width, capture.width);
  assert.equal(metadata.height, capture.height);
  assert.ok(!metadata.orientation || metadata.orientation === 1, "Publish an upright asset instead of relying on EXIF rotation");
});

test("served iPad captures are all registered in the product capture manifest", () => {
  const registered = new Set(Object.values(captures).map(capture => path.basename(capture.src)));
  const files = fs.readdirSync(path.join(__dirname, "../public/app")).filter(name => /ipad.*\.(png|webp|jpe?g)$/i.test(name));
  assert.ok(files.length > 0);
  for (const file of files) assert.ok(registered.has(file), `Unregistered iPad capture: ${file}`);
});
