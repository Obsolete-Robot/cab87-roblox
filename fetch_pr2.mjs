async function run() {
  try {
    const res = await fetch("https://api.github.com/repos/dbokser/Road-Maker/pulls/1");
    console.log("PR response status:", res.status);
    const data = await res.json();
    console.log("data:", JSON.stringify(data, null, 2));
  } catch (err) {
    console.error(err);
  }
}
run();
