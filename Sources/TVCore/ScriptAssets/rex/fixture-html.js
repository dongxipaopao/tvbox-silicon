// Offline sample of a module that needs the host's HTML loader, which this app does not have yet.
WidgetMetadata = {
  id: "fixture.html", title: "Sample HTML module", version: "1.0.0",
  modules: [{ id: "list", title: "Hot", functionName: "loadList", params: [{ name: "page", title: "Page", type: "page", value: "1" }] }]
};
async function loadList(params) {
  const doc = await Widget.html.load("https://example.invalid/list");
  return [];
}
