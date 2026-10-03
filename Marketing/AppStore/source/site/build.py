# The served pages: each .src.html with base.css inlined, one request a page
# (the simulator waits on a lookup for each request to a .localhost name).
import os
here = os.path.dirname(os.path.abspath(__file__))
css = open(os.path.join(here, "base.css")).read()
for name in sorted(os.listdir(here)):
    if name.endswith(".src.html"):
        page = open(os.path.join(here, name)).read().replace('<link rel="stylesheet" href="/base.css">', "<style>" + css + "</style>")
        open(os.path.join(here, name.replace(".src", "")), "w").write(page)
        print("built", name.replace(".src", ""))
