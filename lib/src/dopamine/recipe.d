module dopamine.recipe;

import dopamine.dependency;

class Recipe {
    string name;
    string ver;
    string repo;
    Dependency[] dependencies;
}
