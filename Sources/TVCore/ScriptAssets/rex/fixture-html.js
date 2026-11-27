// Offline sample of a module that needs a raw TMDB lookup, which this app does not have yet.
WidgetMetadata = {
  id: "fixture.html", title: "Sample TMDB module", version: "1.0.0",
  modules: [{ id: "list", title: "Hot", functionName: "loadList", params: [{ name: "page", title: "Page", type: "page", value: "1" }] }]
};
async function loadList(params) {
  const data = await Widget.tmdb.get("trending/all/day", { params: { language: "zh-CN" } });
  return [];
}
