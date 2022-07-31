module app;

import url;

void main()
{
    const url = parseURL("https://dopamine-pm.org/docs");
    assert(url.scheme == "https");
    assert(url.host == "dopamine-pm.org");
    assert(url.path == "/docs");
}
