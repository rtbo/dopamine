module dopamine.pack;

import dopamine.paths;
import dopamine.recipe;

import std.format;

class InvalidPackageException : Exception
{
    string path;
    string reason;

    this(string path, string reason, string file = __FILE__, size_t line = __LINE__)
    {
        super(format("package %s is invalid: %s", path, reason), file, line);
        this.path = path;
        this.reason = reason;
    }
}

class InvalidRecipeException : InvalidPackageException
{
    this(string path, string reason, string file = __FILE__, size_t line = __LINE__)
    {
        super(path, format("Invalid recipe: %s", reason), file, line);
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
        if (!_dir.hasRecipeFile)
        {
            throw new InvalidPackageException(path, "has no dopamine.lua file");
        }

        try
        {
            _recipe = Recipe.parseFile(_dir.recipeFile);
        }
        catch (Exception ex)
        {
            throw new InvalidRecipeException(path, ex.msg);
        }
    }


}
