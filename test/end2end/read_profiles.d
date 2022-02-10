module read_profiles;

import utils;

import std.process;

int main(string[] args)
{
    return drive({
        assertCommandOutput(
            [args[1], "-C", recipeDir("profile"), "profile", "--describe"],
            [
                "Profile ldc-d",
                "Architecture: X86-64",
            ]);
    });
}
