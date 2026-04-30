async function run() {
  try {
    const res = await fetch("https://api.github.com/users/dbokser/repos?per_page=100");
    const data = await res.json();
    console.log("Repos:");
    for (const repo of data) {
      if (repo.name.toLowerCase().includes("road")) {
        console.log(repo.name);
      }
    }
  } catch(e) { console.error(e); }
}
run();
