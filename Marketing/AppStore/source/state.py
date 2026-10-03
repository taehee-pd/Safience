"""Puts the simulator's Safience in one of the screenshot states.
Usage: python3 state.py <container> hero|split|client|start|palette"""
import json, sys, os, uuid
C, mode = sys.argv[1], sys.argv[2]
f = os.path.join(C, "Library/Application Support/Safience/workspace.json")
w = json.load(open(f))
by = {s["name"]: s for s in w["spaces"]}
studio, client, home = by["Studio"], by["Client"], by["Personal"]
def tab(space, part):
    return next(t for t in space["tabs"] if t.get("url") and part in t["url"])
# Titles as the pages give them: a tab whose page hasn't loaded this run shows its title, not its address.
titles = {"mail.html": "Inbox · Post", "week.html": "This week · Week", "canvas.html": "Onboarding v3 · Forma",
          "notes.html": "Launch plan · Margin", "board.html": "Spring release · Lanes"}
for space in (studio, client, home):
    for t in space["tabs"]:
        for page, title in titles.items():
            if page in (t.get("url") or ""): t["title"] = title
for t in client["tabs"]:
    if "notes.localhost" in (t.get("url") or ""): t["title"] = "Brand review · Margin"
    if "canvas.localhost" in (t.get("url") or ""): t["title"] = "Campaign · Forma"
studio["tabs"] = [t for t in studio["tabs"] if t.get("url")]
studio["splits"] = []
w["spaces"] = [studio, client, home]
canvas, notes = tab(studio, "canvas.html"), tab(studio, "notes.html")
if mode in ("hero", "palette"):
    studio["selected"] = canvas["id"]
elif mode == "split":
    studio["splits"] = [{"left": canvas["id"], "right": notes["id"], "ratio": 0.56}]
    studio["selected"] = notes["id"]
elif mode == "client":
    w["spaces"] = [client, studio, home]
    client["selected"] = tab(client, "board.html")["id"]
elif mode == "start":
    new = {"id": str(uuid.uuid4()).upper(), "title": "", "shown": max(t["shown"] for t in studio["tabs"]) + 1}
    studio["tabs"].append(new)
    studio["selected"] = new["id"]
json.dump(w, open(f, "w"))
print("state", mode)
