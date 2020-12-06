# Dopamine PM server

## API

### Users

Create a new user
```
POST    /v1/users
```

Get user
```
GET     /v1/users/{id}
```

### Packages

This section treats the package definitions, that is their recipe to create binaries, but not the built packages themselves.

Create a new package
```
POST    /v1/packages
```

Update a new package (its metadata mainly)
```
PUT     /v1/packages/update
```

Read a package
```
GET     /v1/packages/{id}
```

Publish a new version for a package
```
POST    /v1/packages/{id}/versions
```

Get the available versions of a package
```
GET     /v1/packages/{id}/versions
```

Get the latest version of a package
```
GET     /v1/packages/{id}/versions?latest=true
```

Get a package by name
```
GET     /v1/packages?name={}
```

### Profiles
