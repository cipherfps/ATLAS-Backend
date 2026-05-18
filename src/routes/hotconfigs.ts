import { app } from "..";

export default function () {
  // Newer Fortnite versions request this endpoint during boot.
  // Returning an empty config keeps clients happy and avoids noisy 404s.
  app.get("/hotconfigs/v2/livefn.json", (c) => {
    c.header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    c.header("Pragma", "no-cache");
    c.header("Expires", "0");
    return c.json({});
  });
}

