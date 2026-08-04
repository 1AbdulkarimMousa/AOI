import Alpine from "alpinejs";
import { createIcons, Sparkles } from "lucide";
import "../css/aoi.css";

window.Alpine = Alpine;

const page = document.body.dataset.page;

if (page === "landing") {
  const { registerLanding } = await import("./landing.js");
  registerLanding(Alpine);
}

if (page === "login") {
  const { registerLogin } = await import("./login.js");
  registerLogin(Alpine);
}

if (page === "workspace") {
  const [{ registerWorkspace }, { workspaceTemplate }] = await Promise.all([
    import("./workspace.js"),
    import("./workspace-template.js"),
  ]);
  document.querySelector("#workspace-app").innerHTML = workspaceTemplate;
  registerWorkspace(Alpine);
}

if (page === "administration") {
  const [{ registerAdministration }, { administrationTemplate }] = await Promise.all([
    import("./administration.js"),
    import("./administration-template.js"),
  ]);
  document.querySelector("#administration-app").innerHTML = administrationTemplate;
  registerAdministration(Alpine);
}

Alpine.start();
createIcons({ icons: { Sparkles } });
