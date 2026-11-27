const WidgetMetadata = {
  id: "fixture.list",
  title: "Sample list module",
  version: "1.0.0",
  requiredVersion: "0.0.1",
  globalParams: [],
  modules: [
    { id: "hot", title: "Hot", functionName: "loadHot", params: [
      { name: "page", title: "Page", type: "page" },
      { name: "kind", title: "Kind", type: "enumeration", value: "movie", enumOptions: [ { title: "Movies", value: "movie" }, { title: "Series", value: "tv" } ] } ] },
    { id: "latest", title: "Latest", functionName: "loadLatest", params: [ { name: "page", title: "Page", type: "page" } ] }
  ]
};
function item(n, kind) {
  return { id: "fx:" + kind + n, type: "url", title: (kind === "tv" ? "Sample Series " : "Sample Movie ") + n,
    subtitle: kind + " · 2026", posterPath: "", description: "Fixture item " + n, releaseDate: "2026-01-01", rating: 7 + (n % 3) * 0.5 };
}
async function loadHot(params) {
  const page = Number(params.page) || 1, kind = params.kind || "movie";
  return [1, 2, 3, 4, 5, 6].map(i => item((page - 1) * 6 + i, kind));
}
async function loadLatest(params) {
  const page = Number(params.page) || 1;
  return [1, 2, 3].map(i => item((page - 1) * 3 + i, "movie"));
}
