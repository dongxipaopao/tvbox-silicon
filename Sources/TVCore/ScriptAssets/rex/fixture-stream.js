const WidgetMetadata = {
  id: "fixture.stream",
  title: "Sample stream module",
  version: "1.0.0",
  requiredVersion: "0.0.1",
  globalParams: [],
  modules: [
    { id: "list", title: "Titles", functionName: "loadTitles", params: [ { name: "page", title: "Page", type: "page" } ] },
    { id: "resource", title: "Play lines", functionName: "loadResource", type: "stream", params: [] }
  ]
};
// Offline and keyless. The addresses use the reserved .invalid domain and never play; they only show the lines list.
const titles = [
  { id: "fx-ok", title: "Lines sample" },
  { id: "fx-none", title: "No lines sample" },
  { id: "fx-fail", title: "Failure sample" },
  { id: "fx-shape", title: "Wrong shape sample" }
];
async function loadTitles() {
  return titles.map(t => ({ id: t.id, type: "url", title: t.title, subtitle: "stream", posterPath: "", description: "Fixture title", releaseDate: "2026-01-01", rating: 7 }));
}
async function loadResource(params) {
  const id = String(params.id || params.link || ""), episode = Number(params.episode || 1);
  if (id === "fx-ok") return [
    { name: "Line A · episode " + episode, description: "https fixture line", url: "https://example.invalid/a/" + episode + ".m3u8", headers: { Referer: "https://example.invalid/" } },
    { name: "Line B (not a web address)", description: "ftp fixture line", url: "ftp://example.invalid/b/" + episode + ".mp4" },
    { name: "Line C (no address)" }
  ];
  if (id === "fx-none") return [];
  if (id === "fx-shape") return { items: [] };
  throw new Error("该集暂无可用线路（样例失败）");
}
