# PGD

PostgreSQL D bindings and D high level usage library

PGD has no dependency and is designed to be used either synchronously or asynchronously.
The waiting code necessary for async execution are not written.
Typically, PGD would be extended in a vibe-d application which will provide the waiting routines
through vibe-core.
