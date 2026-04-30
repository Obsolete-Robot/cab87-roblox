async function run() {
  try {
    const patchRes = await fetch("https://github.com/dbokser/Road-Maker/pull/1.patch");
    if (patchRes.ok) {
        console.log("PATCH CONTENT:", await patchRes.text());
        return;
    }
    const diffRes = await fetch("https://patch-diff.githubusercontent.com/raw/dbokser/Road-Maker/pull/1.diff");
    console.log("DIFF CONTENT:", await diffRes.text());
  } catch (err) {
    console.error(err);
  }
}
run();
