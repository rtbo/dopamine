module dopamine.pack;

import dopamine.paths;
import dopamine.recipe;

import std.format;

class InvalidPackageException : Exception
{
    string path;
    string reason;

    this(string path, string reason)
    {
        super(format("package %s is invalid: %s", path, reason));
        this.path = path;
        this.reason = reason;
    }
}

class InvalidRecipeException : InvalidPackageException
{
    this(string path, string reason)
    {
        super(path, format("Invalid recipe: %s", reason));
    }
}

class Package
{
    private PackageDir _dir;
    private Recipe _recipe;

    this(string path)
    {
        _dir = PackageDir(path);
        if (!_dir.exists)
        {
            throw new InvalidPackageException(path, "directory does not exist");
        }
        if (!_dir.hasDopamineFile)
        {
            throw new InvalidPackageException(path, "has no dopamine.lua file");
        }

        try
        {
            _recipe = Recipe.parseFile(_dir.dopamineFile);
        }
        catch (Exception ex)
        {
            throw new InvalidRecipeException(path, ex.msg);
        }
    }


}
